import { useCallback, useContext, useState } from "react";
import ModePanel from "./ModePanel";
import PresenterArea from "./PresenterArea";
import HlsPlayer from "./HlsPlayer";
import { Channel } from "phoenix";
import { ScreenTypeContext } from "../../utils/ScreenTypeContext";
import { RotateLeft } from "react-swm-icon-pack";
import { switchAskingForBeingPresenter } from "../../utils/channelUtils";
import MobileHlsBar from "./MobileHlsBar";
import { MobileBottomPanel } from "./MobileBottomPanel";
import { useAutoHideMobileBottomBar } from "../../utils/useAutoHideMobileBottomBar";
import type { Client, ChatMessage, CardStatus } from "../../types/types";

import "../../../css/event/streamarea.css";

type StreamAreaProps = {
  client: Client;
  amIPresenter: boolean;
  presenterName: string;
  eventChannel: Channel | undefined;
  privateChannel: Channel | undefined;
  eventTitle: string;
  chatMessages: ChatMessage[];
  isChatLoaded: boolean;
  isBannedFromChat: boolean;
  attachVideo: (videoElem: HTMLVideoElement | null) => void;
};

const StreamArea = ({
  client,
  amIPresenter,
  presenterName,
  eventChannel,
  privateChannel,
  eventTitle,
  chatMessages,
  isChatLoaded,
  isBannedFromChat,
  attachVideo,
}: StreamAreaProps) => {
  const { device, orientation } = useContext(ScreenTypeContext);
  const [card, setCard] = useState<CardStatus>("hidden");
  const showMobileBottomBar = device === "mobile" || orientation === "portrait";

  useAutoHideMobileBottomBar(setCard);

  const switchAsking = useCallback(
    (isAsking: boolean) => {
      switchAskingForBeingPresenter(eventChannel, client.email, isAsking);
    },
    [eventChannel, client]
  );

  return (
    <div className="StreamArea">
      {device === "desktop" && (
        <ModePanel presenterName={presenterName} eventChannel={eventChannel} amIPresenter={amIPresenter} />
      )}
      <div className="Stream">
        {amIPresenter ? (
          <PresenterArea client={client} privateChannel={privateChannel} eventChannel={eventChannel} />
        ) : (
          <div className="HlsDiv">
            {presenterName ? (
              <>
                <HlsPlayer
                  attachVideo={attachVideo}
                  presenterName={presenterName}
                  eventChannel={eventChannel}
                  addMessage={undefined}
                  setCard={setCard}
                />
                {device === "mobile" && (
                  <MobileHlsBar
                    client={client}
                    eventTitle={eventTitle}
                    amIPresenter={amIPresenter}
                    switchAsking={switchAsking}
                  />
                )}
              </>
            ) : (
              <div className="HlsStream">
                <div className="WaitText">
                  <RotateLeft className="RotateIcon" />
                  Waiting for the live stream to start...
                </div>
              </div>
            )}
          </div>
        )}

        {showMobileBottomBar && (
          <MobileBottomPanel
            eventChannel={eventChannel}
            isChatLoaded={isChatLoaded}
            isBannedFromChat={isBannedFromChat}
            client={client}
            chatMessages={chatMessages}
            card={card}
            eventTitle={eventTitle}
            onBarClick={() => setCard("hidden")}
          />
        )}
      </div>
    </div>
  );
};

export default StreamArea;
