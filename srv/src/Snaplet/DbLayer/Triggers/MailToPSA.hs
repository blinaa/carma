
module Snaplet.DbLayer.Triggers.MailToPSA
  (sendMailToPSA
  ) where

import Prelude hiding (log)
import Control.Applicative
import Control.Monad
import Control.Monad.Writer.Strict
import Control.Concurrent

import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as B
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TL
import Text.Printf
import Data.Char
import Data.Maybe
import Data.Time
import Data.Time.Clock.POSIX
import System.Locale (defaultTimeLocale)

import System.Log.Simple
import System.Log.Simple.Base (scoperLog)
import Data.Configurator (require)
import Network.Mail.Mime

import Snap.Snaplet (getSnapletUserConfig)
import Snaplet.DbLayer.Triggers.Types
import Snaplet.DbLayer.Triggers.Dsl


sendMailToPSA :: MonadTrigger m b => ByteString -> m b ()
sendMailToPSA actionId = do
  svcId  <- get actionId "parentId"
  isValidSvc <- case B.split ':' svcId of
    "tech":_
      -> (`elem` ["charge", "starter", "condition"])
      <$> get svcId "techType"
    "towage":_ -> return True
    _ -> return False
  caseId  <- get actionId "caseId"
  program <- get caseId   "program"
  when (isValidSvc && program `elem` ["peugeot", "citroen"])
    $ sendMailActually actionId


sendMailActually :: MonadTrigger m b => ByteString -> m b ()
sendMailActually actionId = do
    liftDb $ log Trace (T.pack $ "sendMailToPSA(" ++ show actionId ++ ")")
    tz <- liftIO getCurrentTimeZone

    svcId   <- get actionId "parentId"
    caseId  <- get actionId "caseId"
    program <- get caseId   "program"

    let body = do
          fld 4   "BeginOfFile"     <=== "True"
          fld 50  "Assistance Code" <=== case program of
            "peugeot" -> "RUMC01R"
            "citroen" -> "FRRM01R"
            _ -> error $ "Invalid program: " ++ show program
          fld 2   "Country Сode" <=== "RU"
          fld 9   "Task Id"      <===
            case B.readInt $ B.dropWhile (not.isDigit) caseId of
              Just (n,"") -> T.pack $ printf "M%08d" n
              _ -> error $ "Invalid case id: " ++ show caseId

          callDate <- fromMaybe (error "Invalid callDate") . toLocalTime tz
            <$> lift (get caseId "callDate")

          fld 5   "Time of Incident" <=== tmFormat "%H:%M" callDate
          fld 3   "Make"             <=== case program of
            "peugeot" -> "PEU"
            "citroen" -> "CIT"
            _ -> error $ "Invalid program: " ++ show program

          fld 13  "Model"   $ get' caseId "car_model"
          fld 1   "Energie" $ get caseId "car_engine" >>= \case
            "dis" -> return "D"
            _     -> return "E"

          fld 10  "Date put on road" <=== tmFormat "%d/%m/%Y" callDate
          fld 17  "VIN number"       $ get' caseId "car_vin"
          fld 10  "Reg No"           $ get' caseId "car_plateNum"

          fld 150 "Customer effet"   <=== "" -- FIXME:
          fld 150 "Component fault"  <=== "" -- FIXME:

          factServiceStart
            <- fromMaybe (error "Invalid factServiceStart") . toLocalTime tz
            <$> lift (get svcId "times_factServiceStart")

          partnerId <- lift $ get svcId "contractor_partnerId"

          fld 10 "Date of Opening"       <=== tmFormat "%d/%m/%Y" callDate
          fld 10 "Date of Response"      <=== tmFormat "%d/%m/%Y" factServiceStart
          fld 5  "Time of Response"      <=== tmFormat "%H:%M" factServiceStart
          fld 100 "Breakdown Location"   $ get' caseId "caseAddress_address"
          fld 20  "Breakdown Area"       $ get' caseId "city" -- FIXME: len = 3
          fld 100 "Breakdown Service"    $ get' partnerId "name"
          fld 20  "Service Tel Number 1" $ get' partnerId "phone1"
          fld 20  "Service Tel Number 2" $ get' partnerId "closeTicketPhone"
          fld 100 "Patrol Address 1"     $ get' partnerId "addrDeFacto"
          fld 100 "Patrol Address 2"     <===  ""
          fld 100 "Patrol Address V"     <===  ""
          fld 50  "User Name"                $ get' caseId "contact_name"
          fld 20  "User Tel Number"          $ get' caseId "contact_phone1"
          fld 50  "User Name P"
            $ get' caseId "contact_contactOwner" >>= \case
              "0" -> get' caseId "contact_name"
              _   -> get' caseId "contact_ownerName"

          fld 4  "Job Type" <=== case B.split ':' svcId of
            "tech":_ -> "DEPA"
            "towage":_ -> "REMO"
            _ -> error $ "Invalid jobType: " ++ show svcId

          fld 200 "Dealer Address G"  $ get' svcId "towAddress_address"
          fld 200 "Dealer Address 1"  <=== ""
          fld 200 "Dealer Address 2"  <=== ""
          fld 200 "Dealer Address V"  <=== ""
          fld 20  "Dealer Tel Number" $ get' partnerId "phone1"
          fld 4   "End Of File"      <=== "True"

    bodyText <- TL.encodeUtf8 . TL.fromChunks <$> execWriterT body
    let bodyPart = Part "text/plain; charset=utf-8"
          QuotedPrintableText Nothing [] bodyText

    cfg     <- liftDb getSnapletUserConfig
    cfgFrom <- liftIO $ require cfg "psa-smtp-from"
    cfgTo   <- liftIO $ require cfg "psa-smtp-recipients"

    l <- liftDb askLog
    -- FIXME: throws `error` if sendmail exits with error code
    void $ liftIO $ forkIO
      $ scoperLog l (T.concat ["sendMailToPSA(", T.decodeUtf8 actionId, ")"])
      $ renderSendMailCustom "/usr/sbin/exim" ["-t", "-r", T.unpack cfgFrom]
      $ (emptyMail $ Address Nothing cfgFrom)
        {mailTo = map (Address Nothing . T.strip) $ T.splitOn "," cfgTo
        ,mailHeaders
          = [("Subject"
          ,T.concat ["RAMC ", T.decodeUtf8 svcId, " / ", T.decodeUtf8 actionId])]
        ,mailParts = [[bodyPart]]
        }


get' :: MonadTrigger m b => ByteString -> ByteString -> m b Text
get' = (fmap T.decodeUtf8 .) . get

fld :: Monad m => Int -> Text -> m Text -> WriterT [Text] m ()
fld len name f = do
  val <- lift f
  tell [T.concat [name, " : ", T.take len val, "\n"]]

(<===) :: Monad m => (m a -> t) -> a -> t
f <=== v = f $ return v

tmFormat = (T.pack .) . formatTime defaultTimeLocale

toLocalTime :: TimeZone -> ByteString -> Maybe LocalTime
toLocalTime tz tm = case B.readInt tm of
  Just (s,"") -> Just $ utcToLocalTime tz
    $ posixSecondsToUTCTime $ fromIntegral s
  _ -> Nothing
