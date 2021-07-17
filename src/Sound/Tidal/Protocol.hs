-- {-# LANGUAGE DataKinds #-}
-- {-# LANGUAGE GADTs #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Listener protocol

module Sound.Tidal.Protocol where

import Sound.OSC.FD -- (UDP, sendMessage)
import Control.Concurrent
import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Exception
import Control.Monad
import Control.Monad.Trans.Reader (ReaderT, ask, runReaderT)
import Control.Monad.IO.Class (liftIO)

data ClientContext = ClientContext {
    ccTarget :: UDP
  , ccServer :: UDP
  }

type ClientMonad = ReaderT ClientContext IO

initContext :: IO ClientContext
initContext = do
  ccTarget <- openUDP "127.0.0.1" 6011
  ccServer <- udpServer "127.0.0.1" 6012
  pure ClientContext{..}

ping :: ClientMonad ()
ping = do
  send $ message "/ping" mempty
  void $ waitMessageOnAddr "/pong"

codeMsg streamName codeStr = message "/code" [string streamName, string codeStr]

code streamName codeStr = send $ codeMsg streamName codeStr

getCps :: ClientMonad ()
getCps = do
  send $ message "/cps" mempty

send msg = do
  t <- ccTarget <$> ask
  liftIO $ sendMessage t msg

receive = do
  s <- ccServer <$> ask
  mMsg <- liftIO $ recvMessage s
  case mMsg of
    Nothing -> error "recvMessage returns Nothing.. should't happen?"
    Just msg -> pure msg

waitMessageOnAddr addr = do
  msg <- receive
  if messageAddress msg == addr
    then return msg
    else waitMessageOnAddr addr

runClient act = do
  bracket
    initContext
    (\ClientContext{..} -> do
        udp_close ccTarget
        udp_close ccServer)
    (runReaderT act)

delay sec = liftIO $ threadDelay (1000000 *  sec)

demo = do
  code "hello" "sound \"bd bass\""
  code "secondStream" "sound \"~ ht*2\""
  delay 55
  code "hello" "stack [ \n sound \"v*4\" \n , sound \"arpy(3,5)\" ]"
  delay 5
  code "hello" "silence"
  code "secondStream" "silence"

data ServerResponse =
    CodeOk String
  | CodeErr String String
  | CPS Float
  | Highlight {
      hDelta :: Float
    , hCycle :: Float
    , hX0    :: Int
    , hY0    :: Int
    , hX1    :: Int
    , hY1    :: Int
    }

toResponse (Message "/code/ok" [ASCII_String a_ident]) = CodeOk (ascii_to_string a_ident)
toResponse (Message "/code/error" [ASCII_String a_ident, ASCII_String err]) = CodeErr (ascii_to_string a_ident) (ascii_to_string err)
--toResponse (Message "/code/highlight"
--  [ASCII_String a_ident, ASCII_String err]) = CodeErr (ascii_to_string a_ident) (ascii_to_string err)

justdoit = do
  q <- newTChanIO
  stream q

stream srvQ = runClient $ do
  ping
  s <- ccServer <$> ask
  liftIO $ async $ forever $ do
    msg <- recvMessage' s
    atomically $ writeTChan srvQ msg

  liftIO $ async $ forever $ do
    fq <- atomically $ readTChan srvQ
    print fq

  demo

tidalClient :: TChan Message -> TChan Message -> IO ()
tidalClient toTidal fromTidal = runClient $ do
  ping
  s <- ccServer <$> ask
  void $ liftIO $ async $ forever $ do
    msg <- recvMessage' s
    atomically $ writeTChan fromTidal msg

  t <- ccTarget <$> ask
  liftIO $ forever $ do
    msg <- atomically $ readTChan toTidal
    sendMessage t msg

-- utils

recvMessage' s = do
  mMsg <- recvMessage s
  case mMsg of
    Nothing -> error "recvMessage returns Nothing.. should't happen?"
    Just msg -> pure msg


sendCode r x = sendMessage r $ Message "/code" [string "tmp", string x]
