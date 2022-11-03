import React from "react";
import AnimationComponent from "./HeartAnimation";
import ReactHlsPlayer from "react-hls-player";
import HlsControlBar from "./HlsControlBar";
import { Channel } from "phoenix";
import { MediaController } from "media-chrome/dist/react";
import { RotateLeft } from "react-swm-icon-pack";
import "../../../css/event/hlsplayer.css";

type HlsPlayerProps = {
  hlsUrl: string;
  presenterName: string;
  eventChannel: Channel | undefined;
};

const HlsPlayer = ({ hlsUrl, presenterName, eventChannel }: HlsPlayerProps) => {
  return (
    <div className="HlsStream">
      {hlsUrl ? (
        <div className="HlsPlayerWrapper">
          <MediaController className="HlsPlayerWrapper">
            <ReactHlsPlayer
              hlsConfig={{
                liveSyncDurationCount: 2,
                initialLifeManifestSize: 2,
                backBufferLength: 30,
              }}
              autoPlay={true}
              muted={true}
              className="HlsPlayer"
              slot="media"
              src={hlsUrl}
            ></ReactHlsPlayer>
            <HlsControlBar></HlsControlBar>
          </MediaController>
          <div className="HlsTopBar">
            {presenterName && <div className="HlsPresenterName">{presenterName}</div>}
          </div>
          <div className="HlsBottomBar">
            <AnimationComponent eventChannel={eventChannel} />
          </div>
        </div>
      ) : (
        <div className="WaitText">
          <RotateLeft className="RotateIcon" />
          Waiting for the live stream to start...
        </div>
      )}
    </div>
  );
};

export default HlsPlayer;