import React, { useEffect, useState } from "react";
import ModePanel from "./ModePanel";
import PresenterStreams from "./PresenterStreams";
import HlsPlayer from "./HlsPlayer";
import type { Mode, Client } from "../../types";
import { Channel } from "phoenix";
import useCheckScreenType from "../../utils/hooks";
import "../../../css/event/streamarea.css";

type StreamAreaProps = {
  client: Client;
  eventChannel: Channel | undefined;
  privateChannel: Channel | undefined;
};

const StreamArea = ({ client, eventChannel, privateChannel }: StreamAreaProps) => {
  const [mode, setMode] = useState<Mode>("hls");
  const [hlsUrl, setHlsUrl] = useState<string>("");
  const [presenterName, setPresenterName] = useState<string>("");
  const screenType = useCheckScreenType();

  const addHlsUrl = (message: { name: string; playlist_idl: string }): void => {
    const link = window.location.href.split("event")[0] + "video/";
    if (message.playlist_idl) {
      setHlsUrl(`${link}${message.playlist_idl}/index.m3u8`);
      setPresenterName(message.name);
    } else {
      setHlsUrl("");
      setPresenterName("");
    }
  };

  useEffect(() => {
    if (eventChannel) {
      eventChannel.on("playlist_playable", (message) => addHlsUrl(message));
      eventChannel.push("isPlaylistPlayable", {}).receive("ok", (message) => addHlsUrl(message));
    }
  }, [eventChannel]);

  useEffect(() => {
    if (privateChannel) {
      privateChannel.on("presenter_remove", () => setMode("hls"));
    }
  }, [privateChannel]);

  return (
    <div className="StreamArea">
      {screenType.device == "desktop" && (
        <ModePanel
          mode={mode}
          setMode={setMode}
          presenterName={presenterName}
          eventChannel={eventChannel}
          client={client}
        />
      )}
      <div className="Stream">
        {mode == "hls" && (
          <HlsPlayer hlsUrl={hlsUrl} presenterName={presenterName} eventChannel={eventChannel} />
        )}
        <PresenterStreams
          client={client}
          eventChannel={eventChannel}
          mode={mode}
          setMode={setMode}
        />
      </div>
    </div>
  );
};

export default StreamArea;