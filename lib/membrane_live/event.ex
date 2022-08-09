defmodule MembraneLive.Event do
  @moduledoc false

  use GenServer

  require Membrane.Logger
  require Membrane.OpenTelemetry

  alias Membrane.ICE.TURNManager
  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.{HLS, WebRTC}
  alias Membrane.RTC.Engine.MediaEvent
  alias Membrane.RTC.Engine.Message
  alias Membrane.WebRTC.Extension.{Mid, TWCC}
  alias MembraneLive.StorageCleanup

  @mix_env Mix.env()

  def start(init_arg, opts) do
    GenServer.start(__MODULE__, init_arg, opts)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  @impl true
  def init(event_id) do
    Membrane.Logger.info("Spawning room process: #{inspect(self())}")

    turn_mock_ip = Application.fetch_env!(:membrane_live, :integrated_turn_ip)
    turn_ip = if @mix_env == :prod, do: {0, 0, 0, 0}, else: turn_mock_ip

    trace_ctx = Membrane.OpenTelemetry.new_ctx()
    Membrane.OpenTelemetry.attach(trace_ctx)

    span_id = event_span_id(event_id)
    room_span = Membrane.OpenTelemetry.start_span(span_id)
    Membrane.OpenTelemetry.set_attributes(span_id, tracing_metadata())

    rtc_engine_options = [
      id: event_id,
      trace_ctx: trace_ctx,
      parent_span: room_span
    ]

    turn_cert_file =
      case Application.fetch_env(:membrane_live, :integrated_turn_cert_pkey) do
        {:ok, val} -> val
        :error -> nil
      end

    integrated_turn_options = [
      ip: turn_ip,
      mock_ip: turn_mock_ip,
      ports_range: Application.fetch_env!(:membrane_live, :integrated_turn_port_range),
      cert_file: turn_cert_file
    ]

    network_options = [
      integrated_turn_options: integrated_turn_options,
      integrated_turn_domain: Application.fetch_env!(:membrane_live, :integrated_turn_domain),
      dtls_pkey: Application.get_env(:membrane_live, :dtls_pkey),
      dtls_cert: Application.get_env(:membrane_live, :dtls_cert)
    ]

    tcp_turn_port = Application.get_env(:membrane_live, :integrated_tcp_turn_port)
    TURNManager.ensure_tcp_turn_launched(integrated_turn_options, port: tcp_turn_port)

    if turn_cert_file do
      tls_turn_port = Application.get_env(:membrane_live, :integrated_tls_turn_port)
      TURNManager.ensure_tls_turn_launched(integrated_turn_options, port: tls_turn_port)
    end

    {:ok, pid} = Membrane.RTC.Engine.start(rtc_engine_options, [])
    Engine.register(pid, self())
    Process.monitor(pid)

    endpoint = %HLS{
      rtc_engine: pid,
      owner: self(),
      output_directory: "output",
      target_window_duration: :infinity
    }

    :ok = Engine.add_endpoint(pid, endpoint)

    {:ok,
     %{
       playlist_idl: "",
       event_id: event_id,
       rtc_engine: pid,
       peer_channels: %{},
       network_options: network_options,
       trace_ctx: trace_ctx,
       is_playlist_playable: false
     }}
  end

  @impl true
  def handle_info({:add_peer_channel, peer_channel_pid, peer_id}, state) do
    state = put_in(state, [:peer_channels, peer_id], peer_channel_pid)
    Process.monitor(peer_channel_pid)
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message.MediaEvent{to: :broadcast, data: data}, state) do
    for {_peer_id, pid} <- state.peer_channels, do: send(pid, {:media_event, data})

    {:noreply, state}
  end

  @impl true
  def handle_info(%Message.MediaEvent{to: to, data: data}, state) do
    if state.peer_channels[to] != nil do
      send(state.peer_channels[to], {:media_event, data})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(%Message.NewPeer{rtc_engine: rtc_engine, peer: peer}, state) do
    Membrane.Logger.info("New peer: #{inspect(peer)}. Accepting.")
    peer_channel_pid = Map.get(state.peer_channels, peer.id)
    peer_node = node(peer_channel_pid)

    handshake_opts =
      if state.network_options[:dtls_pkey] &&
           state.network_options[:dtls_cert] do
        [
          client_mode: false,
          dtls_srtp: true,
          pkey: state.network_options[:dtls_pkey],
          cert: state.network_options[:dtls_cert]
        ]
      else
        [
          client_mode: false,
          dtls_srtp: true
        ]
      end

    endpoint = %WebRTC{
      rtc_engine: rtc_engine,
      ice_name: peer.id,
      owner: self(),
      integrated_turn_options: state.network_options[:integrated_turn_options],
      integrated_turn_domain: state.network_options[:integrated_turn_domain],
      handshake_opts: handshake_opts,
      log_metadata: [peer_id: peer.id],
      trace_context: state.trace_ctx,
      webrtc_extensions: [Mid, TWCC],
      peer_metadata: peer.metadata,
      filter_codecs: fn {rtp, fmtp} ->
        case rtp.encoding do
          "opus" -> true
          "H264" -> fmtp.profile_level_id === 0x42E01F
          _unsupported_codec -> false
        end
      end
    }

    Engine.accept_peer(rtc_engine, peer.id)
    :ok = Engine.add_endpoint(rtc_engine, endpoint, peer_id: peer.id, node: peer_node)

    {:noreply, state}
  end

  @impl true
  def handle_info(%Message.PeerLeft{peer: peer}, state) do
    Membrane.Logger.info("Peer #{inspect(peer.id)} left RTC Engine")
    {_peer_channel_pid, state} = pop_in(state, [:peer_channels, peer.id])
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message.EndpointCrashed{endpoint_id: endpoint_id}, state) do
    Membrane.Logger.error("Endpoint #{inspect(endpoint_id)} has crashed!")
    peer_channel = state.peer_channels[endpoint_id]

    error_message = "Endpoint has crashed."
    data = MediaEvent.create_error_event(error_message)
    send(peer_channel, {:media_event, data})

    {:noreply, state}
  end

  # media_event coming from client
  @impl true
  def handle_info({:media_event, _from, _event} = msg, state) do
    Engine.receive_media_event(state.rtc_engine, msg)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    if pid == state.rtc_engine do
      event_span_id(state.event_id)
      |> Membrane.OpenTelemetry.end_span()

      {:stop, :normal, state}
    else
      {peer_id, _peer_channel_id} =
        state.peer_channels
        |> Enum.find(fn {_peer_id, peer_channel_pid} -> peer_channel_pid == pid end)

      Engine.remove_peer(state.rtc_engine, peer_id)
      {_elem, state} = pop_in(state, [:peer_channels, peer_id])

      if state.peer_channels == %{}, do: Engine.terminate(state.rtc_engine)

      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:playlist_playable, :audio, _playlist_idl}, state) do
    # TODO: implement detecting when HLS starts
    {:noreply, state}
  end

  @impl true
  def handle_info({:playlist_playable, :video, playlist_idl}, state) do
    state = put_in(state, [:is_playlist_playable], true)
    state = put_in(state, [:playlist_idl], playlist_idl)

    MembraneLiveWeb.Endpoint.broadcast!("event:" <> state.event_id, "playlist_playable", %{
      playlist_idl: playlist_idl
    })

    {:noreply, state}
  end

  @impl true
  def handle_info({:cleanup, _clean_function, stream_id}, state) do
    StorageCleanup.remove_directory(stream_id)
    {:stop, :normal, state}
  end

  @impl true
  def handle_call(:is_playlist_playable, _from, state) do
    {:reply,
     %{is_playlist_playable: state.is_playlist_playable, playlist_idl: state.playlist_idl}, state}
  end

  defp tracing_metadata(),
    do: [
      {:"library.language", :erlang},
      {:"library.name", :membrane_rtc_engine},
      {:"library.version", "server:#{Application.spec(:membrane_rtc_engine, :vsn)}"}
    ]

  defp event_span_id(id), do: "event:#{id}"
end
