{-# LANGUAGE DuplicateRecordFields, RecordWildCards #-}
{-# LANGUAGE DataKinds, TypeOperators #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE LambdaCase #-}

-- Incoming server implementation to provide an API for Era Glonass side
-- and also some debug stuff for internal usage.
module Carma.EraGlonass.Server
     ( serverApplicaton
     ) where

import           Data.Proxy
import           Data.Swagger (Swagger)
import           Data.Monoid ((<>))
import           Text.InterpolatedString.QM
import           Data.Text (Text, intercalate)
import           Data.Text.Encoding (decodeUtf8)
import           Data.Aeson (toJSON)

import           Control.Monad.Reader (MonadReader, asks, runReaderT, ReaderT)
import           Control.Monad.Error.Class (MonadError, throwError, catchError)
import           Control.Monad.Random.Class (MonadRandom)
import           Control.Concurrent.STM.TVar

import           Servant
import           Servant.Swagger (toSwagger)

import           Database.Persist ((==.))
import           Database.Persist.Sql (fromSqlKey)
import           Database.Persist.Types

import           Carma.Monad.STM
import           Carma.Monad.MVar
import           Carma.Monad.Clock
import           Carma.Monad.Thread
import           Carma.Monad.LoggerBus
import           Carma.Monad.PersistentSql
import           Carma.Model.Case.Persistent
import           Carma.Model.CaseSource.Persistent
import           Carma.Model.CaseStatus.Persistent
import           Carma.Model.Usermeta.Persistent
import           Carma.Model.Program.Persistent
import           Carma.Model.SubProgram.Persistent
import           Carma.Model.LegacyTypes
import           Carma.EraGlonass.Instances ()
import           Carma.EraGlonass.Routes
import           Carma.EraGlonass.Types
import           Carma.EraGlonass.Model.CaseEraGlonassFailure.Types
import           Carma.EraGlonass.Model.CaseEraGlonassFailure.Persistent
import           Carma.EraGlonass.Model.CaseEraGlonassCreateRequest.Persistent
import           Carma.EraGlonass.Server.Helpers


type FaliuresAPI
    =  -- GET /debug/failures/count.json
       "count.json" :> Get '[JSON] Word

  :<|> -- GET /debug/failures/list.json?limit=10
       "list.json" :>
       QueryParam "limit" Word :>
       Get '[JSON] [Entity CaseEraGlonassFailure]


type ServerAPI
    =  IncomingAPI
  :<|> "debug" :> (    -- GET /debug/swagger.json
                       "swagger.json" :> Get '[JSON] Swagger

                  :<|> "failures" :> FaliuresAPI

                  :<|> -- GET /debug/background-tasks/count.json
                       "background-tasks" :> "count.json" :> Get '[JSON] Word
                  )

-- WARNING! Way to transform monad here is deprecated in newer Servant version.
--          Read about "hoistServer" from "servant-server" when you will be
--          migrating from lts-9.21 to newer one.
serverApplicaton :: AppContext -> Application
serverApplicaton appContext =
  serve (Proxy :: Proxy ServerAPI) $ enter withReader server

  where withReader' :: ReaderT AppContext Handler a -> Handler a
        withReader' r = runReaderT r appContext

        withReader :: ReaderT AppContext Handler :~> Handler
        withReader = NT withReader'


server
  :: ( MonadReader AppContext m
     , MonadLoggerBus m
     , MonadError ServantErr m
     , MonadPersistentSql m
     , MonadClock m
     , MonadRandom m
     , MonadThread m
     , MonadMVar m
     , MonadSTM m
     )
  => ServerT ServerAPI m

server
  =    egCRM01
  :<|> (    swagger
       :<|> (getFailuresCount :<|> getFailuresList)
       :<|> getBackgroundTasksCount
       )


type EgCrm01Monad m =
   ( MonadReader AppContext m
   , MonadLoggerBus m
   , MonadError ServantErr m
   , MonadPersistentSql m
   , MonadClock m
   , MonadRandom m
   , MonadThread m
   , MonadMVar m
   , MonadSTM m
   )

-- | EG.CRM.01 integration point handler.
--
-- WARNING! For failure cases it returns 200 HTTP status with
--          @EGCreateCallCardResponse@ which have @acceptCode@ that is not @OK@.
egCRM01
  :: EgCrm01Monad m
  => EGCreateCallCardRequest
  -> m EGCreateCallCardResponse

egCRM01 (EGCreateCallCardRequestIncorrect msg badReqBody) = do
  logError [qmb| {EgCrm01}: Failed to parse request body, error message: {msg}
                 Saving data of this failure to the database in separated \
                 thread and returning response... |]

  logDebug [qms| {EgCrm01}: Saving failure data to the database
                            (but returning proper response notwithstanding
                             if this failure data saving is succeeded or
                             failed by running it in background)... |]

  -- Saving failure data in background
  inBackground $ do
    time <- getCurrentTime

    failureId <-
      runSqlProtected
        [qm| {EgCrm01}: Failed to save failure data to the database! |]
        $ insert CaseEraGlonassFailure
        { caseEraGlonassFailureCtime = time
        , caseEraGlonassFailureIntegrationPoint = EgCrm01
        , caseEraGlonassFailureRequestBody = Just badReqBody
        , caseEraGlonassFailureResponseId = Nothing
        , caseEraGlonassFailureComment = Just [qm| Error message: {msg} |]
        }

    logError [qms| {EgCrm01}:
                   Failure data is successfully saved to the database.
                   Failure id: {fromSqlKey failureId} |]

  logDebug [qms| {EgCrm01}: Producing random response id
                            for failure response... |]

  randomResponseId <- getRandomResponseId

  logError [qms| {EgCrm01}: Response id for failure response is:
                            "{randomResponseId}" |]

  pure EGCreateCallCardResponseFailure
     { responseId = randomResponseId
     , acceptCode = IncorrectFormat
     , statusDescription = Just "400 Bad Request"
     }

egCRM01 reqBody@EGCreateCallCardRequest {..} = handleFailure $ do
  time             <- getCurrentTime
  randomResponseId <- getRandomResponseId

  logDebug [qms|
    {logPfx} Creation time: "{time}", response id: "{randomResponseId}".
    Finding any "Program" which have "SubProgram" which is Era Glonass
    participant (since "Program" is required field of "Case" model so we
    couldn't leave it empty) then creating "Case" and
    "CaseEraGlonassCreateRequest" in single transaction...
  |]

  ( caseId                :: CaseId,
    caseEGCreateRequestId :: CaseEraGlonassCreateRequestId,
    anyEGSubProgram       :: SubProgramId,
    anyEGProgram          :: ProgramId ) <-

    runSqlProtected
      [qms| {logPfx} Failed to create "Case" and "CaseEraGlonassCreateRequest"
                     for Era Glonass Call Card! |] $ do

      logDebug [qms| {logPfx} Obtaining Era Glonass participant "SubProgram"
                              and its "Program"... |]

      (anyEGProgram :: ProgramId, anyEGSubProgram :: SubProgramId) <-
        selectFirst [SubProgramEraGlonassParticipant ==. True] [] >>= \case

          Just subProgram -> pure
            ( subProgramParent $ entityVal subProgram
            , entityKey subProgram
            )

          Nothing -> do
            let logMsg = [qns| Not found any "SubProgram" for "Case"
                               which is Era Glonass participant! |]

            logError [qm| {logPfx} {logMsg} |]
            throwError err500 { errBody = logMsg }

      logDebug [qmb| {logPfx} Era Glonass participant "SubProgram" \
                              and its "Program" are successfully obtained:
                              \  "SubProgram" id: {fromSqlKey anyEGSubProgram};
                              \  "Program" id: {fromSqlKey anyEGProgram}. |]

      logDebug [qms| {logPfx} Creating "Case"... |]

      caseId <-
        insert Case
          { caseCallDate = Just time
          , caseVwcreatedate = Nothing
          , caseCallTaker = admin
          , caseCustomerComment = Nothing

          , caseContact_name = Just $ fromEGCallerFullName callerFullName
          , caseContact_phone1 =
              Just $ Phone $ fromEGPhoneNumber callerPhoneNumber
          , caseContact_phone2 = Just $ Phone $ fromEGPhoneNumber atPhoneNumber
          , caseContact_phone3 = Nothing
          , caseContact_phone4 = Nothing
          , caseContact_email = Nothing
          , caseContact_contactOwner = Nothing
          , caseContact_ownerName = Nothing
          , caseContact_ownerPhone1 = Nothing
          , caseContact_ownerPhone2 = Nothing
          , caseContact_ownerPhone3 = Nothing
          , caseContact_ownerPhone4 = Nothing
          , caseContact_ownerEmail = Nothing

          , caseProgram = anyEGProgram
          , caseSubprogram = Nothing

          , caseContractIdentifier = Just $ decodeUtf8 $ fromEGVin $ vin vehicle

          , caseCar_vin = Just $ decodeUtf8 $ fromEGVin $ vin vehicle
          , caseCar_make = Nothing
          , caseCar_plateNum = Just $ registrationNumber vehicle
          , caseCar_makeYear = Nothing
          , caseCar_color = Just $ color vehicle
          , caseCar_buyDate = Nothing
          , caseCar_firstSaleDate = Nothing
          , caseCar_mileage = Nothing
          , caseCar_engine = egPropulsionToEngineId <$> propulsion vehicle
          , caseCar_liters = Nothing

          , caseCaseAddress_address =
              case gis of
                   [] -> Nothing
                   (EGCreateCallCardRequestGis {..} : _) -> let
                     partsList =
                       filter (/= mempty) $
                         ( if regionName == settlementName
                              then [regionName]
                              else [regionName, settlementName]
                         ) <> [streetName, building]
                     in Just $ PickerField $ Just $ intercalate ", " partsList
          , caseCaseAddress_comment = Just locationDescription
          , caseCaseAddress_notRussia = Nothing
          , caseCaseAddress_coords = let
              lon, lat, toAngularMillisecondsCoeff :: Double
              lon = fromIntegral $ fromEGLongitude lastTrustedLongitude
              lat = fromIntegral $ fromEGLatitude lastTrustedLatitude
              toAngularMillisecondsCoeff = 3600 * 1000
              toGradus = (/ toAngularMillisecondsCoeff)
              in Just $ PickerField $ Just [qm| {toGradus lon},{toGradus lat} |]
          , caseCaseAddress_map = Nothing
          , caseTemperature = Nothing
          , caseRepair = Nothing
          , caseAccord = Nothing
          , caseDealerCause = Nothing
          , caseCaseStatus = front
          , casePsaExportNeeded = Nothing
          , casePsaExported = Nothing
          , caseClaim = Nothing

          , caseFiles = Nothing
          , caseSource = eraGlonass
          , caseAcStart = Nothing
          , caseIsCreatedByEraGlonass = True
          }

      logDebug [qmb| {logPfx} "Case" is successfully created:
                              \  "Case" id: {fromSqlKey caseId}. |]

      logDebug [qms| {logPfx} Creating "CaseEraGlonassCreateRequest"... |]

      caseEGCreateRequestId <-
        insert CaseEraGlonassCreateRequest
          { caseEraGlonassCreateRequestCtime          = time
          , caseEraGlonassCreateRequestAssociatedCase = caseId
          , caseEraGlonassCreateRequestRequestId      = requestId
          , caseEraGlonassCreateRequestCallCardId     = cardIdCC
          , caseEraGlonassCreateRequestResponseId     = randomResponseId
          }

      logDebug [qmb| {logPfx} "CaseEraGlonassCreateRequest" is \
                              successfully created:
                              \  "CaseEraGlonassCreateRequest" id: \
                                   {fromSqlKey caseId}. |]

      pure (caseId, caseEGCreateRequestId, anyEGSubProgram, anyEGProgram)

  logDebug [qmb| {logPfx} "Case" and "CaseEraGlonassCreateRequest" \
                          are successfully created:
                          \  Found Era Glonass participant "SubProgram" id: \
                               {fromSqlKey anyEGSubProgram};
                          \  Found "Program" id: {fromSqlKey anyEGProgram};
                          \  "Case" id: {fromSqlKey caseId};
                          \  "CaseEraGlonassCreateRequest" id: \
                               {fromSqlKey caseEGCreateRequestId}. |]

  logDebug [qm| {logPfx} Responding about success... |]

  pure EGCreateCallCardResponse
     { responseId        = randomResponseId
     , cardidProvider    = [qm| {fromSqlKey caseId} |]
     , acceptId          = fromEGCallCardId cardIdCC
     , requestId         = requestId
     , acceptCode        = OK
     , statusDescription = Nothing
     }

  where
    logPfx :: Text
    logPfx = [qms| Incoming Creating Call Card request
                   (Call Card id: "{fromEGCallCardId cardIdCC}",
                    Request id: "{fromRequestId requestId}"): |]

    handleFailure
      :: EgCrm01Monad m
      => m EGCreateCallCardResponse
      -> m EGCreateCallCardResponse
    handleFailure m =
      m `catchError` \exception -> do
        logError [qms| {logPfx} Request handler is failed
                                with exception: {exception} |]

        logDebug [qms| {logPfx} Producing random response id
                                for failure response... |]

        randomResponseId <- getRandomResponseId

        logError [qms| {logPfx} Response id for failure response is:
                                "{randomResponseId}" |]

        logDebug [qms| {logPfx} Saving failure data to the database
                                (but returning proper response notwithstanding
                                 if this failure data saving is succeeded or
                                 failed by running it in background)... |]

        -- Saving failure data in background
        inBackground $ do
          time <- getCurrentTime

          failureId <-
            runSqlProtected
              [qm| {logPfx} Failed to save failure data to the database! |]
              $ insert CaseEraGlonassFailure
              { caseEraGlonassFailureCtime = time
              , caseEraGlonassFailureIntegrationPoint = EgCrm01
              , caseEraGlonassFailureRequestBody = Just $ toJSON reqBody
              , caseEraGlonassFailureResponseId = Just randomResponseId
              , caseEraGlonassFailureComment = Just
                  [qm| Request handler is failed, exception: {exception} |]
              }

          logDebug [qms| {logPfx}
                         Failure data is successfully saved to the database.
                         Failure id: {fromSqlKey failureId} |]

        pure EGCreateCallCardResponseFailure
           { responseId = randomResponseId
           , acceptCode = InternalError
           , statusDescription = Just
               [qm| Request handling is failed with exception: {exception} |]
           }


swagger :: Applicative m => m Swagger
swagger = pure $ toSwagger (Proxy :: Proxy IncomingAPI)


getFailuresCount
  :: ( MonadReader AppContext m
     , MonadLoggerBus m
     , MonadError ServantErr m
     , MonadPersistentSql m
     )
  => m Word

getFailuresCount = do
  logDebug [qn| Obtaining EG failures total count... |]

  totalCount <-
    fromIntegral <$>
      runSqlProtected
        [qn| Failed to request EG failures total count! |]
        (count ([] :: [Filter CaseEraGlonassFailure]))

  logDebug [qm| Total EG failures is obtained: {totalCount} |]
  pure totalCount


getFailuresList
  :: ( MonadReader AppContext m
     , MonadLoggerBus m
     , MonadError ServantErr m
     , MonadPersistentSql m
     )
  => Maybe Word
  -> m [Entity CaseEraGlonassFailure]

getFailuresList Nothing = do
  logError [qn| Attempt to obtain EG failures list without specified limit! |]

  throwError err400
    { errBody = [qns| Getting EG failures list
                      without specified limit isn't allowed! |] }

getFailuresList (Just n) = do
  logDebug [qm| Obtaining EG failures list limited to last {n} elements... |]

  result <-
    runSqlProtected
      [qn| Failed to request EG failures list! |]
      $ selectList [] [ Desc CaseEraGlonassFailureId
                      , LimitTo $ fromIntegral n
                      ]

  logDebug [qm| EG failures list is obtained, total elements: {length result} |]
  pure result


getBackgroundTasksCount
  :: ( MonadReader AppContext m
     , MonadLoggerBus m
     , MonadSTM m
     )
  => m Word

getBackgroundTasksCount = do
  logDebug [qn| Reading background tasks counter... |]
  result <- asks backgroundTasksCounter >>= atomically . readTVar
  logDebug [qm| Background tasks count: {result} |]
  pure result
