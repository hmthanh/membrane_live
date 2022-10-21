defmodule MembraneLiveWeb.RecordingsView do
  use MembraneLiveWeb, :view
  alias MembraneLiveWeb.WebinarView

  # credo:disable-for-this-file

  def render("index.json", %{webinars: webinars}) do
    %{webinars: render_many(webinars, WebinarView, "webinar.json")}
  end

  def render("show.json", %{webinar: webinar}) do
    %{webinar: render_one(webinar, WebinarView, "webinar.json")}
  end

  def render("webinar.json", %{webinar: webinar}) do
    %{
      uuid: webinar.uuid,
      title: webinar.title,
      start_date: webinar.start_date,
      description: webinar.description,
      presenters: webinar.presenters
    }
  end
end
