module AppHandlers.Settings.Drivers
    ( assignService
    , cancelService
    , createDriver
    , deleteDriver
    , getDrivers
    , sendSMS
    , showDriverLocation
    , updateDriver
    ) where

import           Control.Monad                      (unless, void, when)
import           Data.Aeson                         (ToJSON,
                                                     Value (Number, String),
                                                     genericToJSON, object,
                                                     toJSON)
import           Data.Aeson.Types                   (defaultOptions,
                                                     fieldLabelModifier)
import           Data.ByteString                    (ByteString)
import qualified Data.ByteString.Char8              as BS
import           Data.Char                          (isDigit)
import           Data.List                          (find)
import           Data.Maybe                         (fromMaybe)
import           Data.Text                          (Text)
import qualified Data.Text                          as T
import           Database.PostgreSQL.Simple.FromRow
import           Database.PostgreSQL.Simple.SqlQQ
import           GHC.Generics                       (Generic)
import           Snap
import           Snap.Snaplet.PostgresqlSimple      (Only (..), execute, query)

import           AppHandlers.MobileAPI              (androidVersionAndURL)
import           AppHandlers.Users
import           Application
import           Carma.Model
import qualified Carma.Model.Usermeta               as Usermeta
import           Carma.Utils.Snap
import qualified Data.Model.Patch                   as Patch
import           Snaplet.Auth.PGUsers


data Driver = Driver
    { _id        :: Int
    , _partnerId :: Int
    , _phone     :: String
    , _password  :: String
    , _name      :: String
    , _plateNum  :: Maybe String
    , _isActive  :: Bool
    , _serviceId :: Maybe Int -- услуга, над которой работает водитель
    } deriving (Show, Generic)

instance FromRow Driver where
    fromRow = Driver <$> field
                     <*> field
                     <*> field
                     <*> field
                     <*> field
                     <*> field
                     <*> field
                     <*> field

instance ToJSON Driver where
    toJSON = genericToJSON defaultOptions
             { fieldLabelModifier = dropWhile (== '_')}

instance ToJSON (Only Int) where
    toJSON (Only i) = Number $ fromIntegral i


phonePrefix :: Text
phonePrefix = "+7"

phoneLength :: Int
phoneLength = 10 -- length without phonePrefix


isValidPhone :: Text -> Bool
isValidPhone phone =
  phonePrefix `T.isPrefixOf` phone &&
  T.length number == phoneLength &&
  T.all isDigit number

    where number = T.drop (T.length phonePrefix) phone


isValidPassword :: Text -> Bool
isValidPassword password =
  T.length password >= 4 &&
  T.all isDigit password


getNotEmptyParam :: ByteString -> Handler a b Text
getNotEmptyParam param = do
  value <- T.strip . fromMaybe (error paramNotSpecified) <$> getParamT param
  when (T.null value) (error paramInvalid)

  return value

  where paramNotSpecified = BS.unpack param ++ " not specified"
        paramInvalid = "invalid " ++ BS.unpack param


getParamBool :: ByteString -> Handler a b Bool
getParamBool param =
  getParam param >>= \p ->
  return $ case p of
             Nothing      -> error paramNotSpecified
             Just "true"  -> True
             Just "false" -> False
             Just v       -> error $ invalidValue v

    where paramNotSpecified = BS.unpack param ++ " not specified"
          invalidValue v = "invalid value " ++ show v ++ " for " ++
                           BS.unpack param


getPhoneParam :: ByteString -> Handler a b Text
getPhoneParam param =
  getNotEmptyParam param >>= \p ->
      if isValidPhone p
      then return p
      else error "invalid password"


getDrivers :: AppHandler ()
getDrivers = checkAuthCasePartner $ do
  Just user <- currentUserMeta
  let Just (Ident partnerId) = Patch.get user Usermeta.ident

  drivers :: [Driver] <- query [sql|
    SELECT id, partner, phone, coalesce(password, ''::text)
         , name, plateNum, isActive, null
      FROM "CasePartnerDrivers"
     WHERE partner = ?
     ORDER BY name
  |] $ Only partnerId

  -- список (водитель,сервис) для незакрытых заявок
  services :: [(Int, Int)] <- query [sql|
    SELECT driverId
         , serviceId
      FROM driverServiceQueue
     WHERE driverId IN (SELECT id FROM "CasePartnerDrivers" WHERE partner = ?)
       AND closed IS NULL
  |] $ Only partnerId

  writeJSON $ map (\driver@(Driver i _ _ _ _ _ _ _) ->
                       case find (\s -> fst s == i) services of
                         Just (_driverId, serviceId) ->
                             driver {_serviceId = Just serviceId}
                         Nothing      -> driver
                  ) drivers


createDriver :: AppHandler ()
createDriver = checkAuthCasePartner $ do
  Just user <- currentUserMeta
  let Just (Ident partnerId) = Patch.get user Usermeta.ident

  phone <- getPhoneParam "phone"

  password <- getNotEmptyParam "password"
  unless (isValidPassword password) (error "invalid password")

  name <- getNotEmptyParam "name"
  plateNum <- T.strip . fromMaybe "" <$> getParamT "plateNum"
  isActive <- getParamBool "isActive"

  driverId :: [Only Int] <- query [sql|
    INSERT INTO "CasePartnerDrivers"
           (partner, phone, password, name, platenum, isActive)
    VALUES (?, ?, ?, ?, ?, ?)
    RETURNING id
  |] ( partnerId
     , phone
     , password
     , name
     , plateNum
     , isActive
     )

  writeJSON driverId


updateDriver :: AppHandler ()
updateDriver = checkAuthCasePartner $ do
  Just user <- currentUserMeta
  let Just (Ident partnerId) = Patch.get user Usermeta.ident

  driverId <- fromMaybe (error "invalid driver id") <$> getIntParam "driverId"

  phone <- getPhoneParam "phone"

  password <- getNotEmptyParam "password"
  unless (isValidPassword password) (error "invalid password")

  name <- getNotEmptyParam "name"
  plateNum <- T.strip . fromMaybe "" <$> getParamT "plateNum"
  isActive <- getParamBool "isActive"

  updatedDriverId :: [Only Int] <- query [sql|
    UPDATE "CasePartnerDrivers"
       SET phone = ?
         , password = ?
         , name = ?
         , plateNum = ?
         , isActive = ?
     WHERE id = ? AND partner = ?
    RETURNING id;
  |] ( phone
     , password
     , name
     , plateNum
     , isActive
     , driverId
     , partnerId
     )

  writeJSON updatedDriverId


deleteDriver :: AppHandler ()
deleteDriver = checkAuthCasePartner $ do
  Just user <- currentUserMeta
  let Just (Ident partnerId) = Patch.get user Usermeta.ident

  driverId <- fromMaybe (error "invalid driver id") <$> getIntParam "driverId"

  deletedDriverId :: [Only Int] <- query [sql|
    DELETE
      FROM "CasePartnerDrivers"
     WHERE id = ? AND partner = ?
    RETURNING id
  |] ( driverId
     , partnerId
     )

  writeJSON deletedDriverId


sendSMS :: AppHandler ()
sendSMS = checkAuthCasePartner $ do
  driverId <- fromMaybe (error "invalid driver id") <$> getIntParam "driverId"

  cfg <- getSnapletUserConfig

  (_, url) <- androidVersionAndURL cfg
  let message = T.unwords [ "Вы зарегистрированы в системе РАМК."
                          , "Скачайте по ссылке приложение:"
                          , url
                          ]

  smsId :: [Only Int] <- query [sql|
    SELECT send_sms_invite_driver(?, ?)
  |] (driverId, message)

  writeJSON smsId


showDriverLocation :: AppHandler ()
showDriverLocation = checkAuthCasePartner $ do
  Just user <- currentUserMeta
  let Just (Ident partnerId) = Patch.get user Usermeta.ident

  driverId <- fromMaybe (error "invalid driver id") <$> getIntParam "driverId"

  driver :: [(String, String, Maybe String, Maybe Double, Maybe Double)] <- query [sql|
    SELECT name
         , phone
         , plateNum
         , ST_X(ST_EndPoint(geometry(locations))) as latitude
         , ST_Y(ST_EndPoint(geometry(locations))) as longitude
      FROM "CasePartnerDrivers" d
         , driverServiceQueue q
     WHERE d.id = ?
       AND d.partner = ?
       AND d.currentServiceId = q.serviceId
  |] ( driverId
     , partnerId
     )

  case driver of
    [(name, phone, plateNum, latitude, longitude)] ->
        writeJSON [ object [ ("name", String $ T.pack name)
                           , ("phone", String $ T.pack phone)
                           , ("plateNum", toJSON plateNum)
                           , ("latitude", toJSON latitude)
                           , ("longitude", toJSON longitude)
                           ]
                  ]
    _ -> writeJSON ([] :: [Int])


-- | Назначить услугу на водителя
assignService :: AppHandler ()
assignService = checkAuthCasePartner $ do
  Just user <- currentUserMeta
  let Just (Ident partnerId) = Patch.get user Usermeta.ident

  driverId  <- fromMaybe (error "invalid driver id")  <$> getIntParam "driverId"
  serviceId <- fromMaybe (error "invalid service id") <$> getIntParam "serviceId"

  [Only (count :: Int)] <- query [sql|
    SELECT count(*)
      FROM "CasePartnerDrivers"
     WHERE id = ? AND partner = ?
  |] ( driverId
     , partnerId
     )

  if count == 1
  then do
    [Only (queueId :: Int)] <- query [sql|
      INSERT INTO driverServiceQueue (driverId, serviceId)
      VALUES (?, ?)
      RETURNING id
    |] ( driverId
       , serviceId
       )
    -- сохранить номер текущей заявки
    void $ execute [sql|
      UPDATE "CasePartnerDrivers"
         SET currentServiceId = ?
       WHERE id = ?
    |] ( serviceId
       , driverId
       )

    writeJSON queueId

  else error "invalid driver id/partner id"


cancelService :: AppHandler ()
cancelService = checkAuthCasePartner $ do
  driverId  <- fromMaybe (error "invalid driver id")  <$> getIntParam "driverId"
  serviceId <- fromMaybe (error "invalid service id") <$> getIntParam "serviceId"

  ids :: [Only Int] <- query [sql|
    DELETE
      FROM driverServiceQueue
     WHERE driverId = ?
       AND serviceId = ?
    RETURNING id
  |] ( driverId
     , serviceId
     )

  void $ execute [sql|
    UPDATE "CasePartnerDrivers"
       SET currentServiceId = NULL
     WHERE id = ?
  |] $ Only driverId

  writeJSON $ case ids of
                (Only i:_) -> i
                _          -> 0
