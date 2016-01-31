{-# LANGUAGE DoAndIfThenElse #-}
{-# LANGUAGE QuasiQuotes #-}

{-|

Combinators and helpers for user permission checking and serving user
data/states.

-}

module AppHandlers.Users
    ( chkAuth
    , chkAuthLocal
    , chkAuthAdmin
    , chkAuthPartner

    , chkAuthRoles
    , hasAnyOfRoles
    , hasNoneOfRoles

    , serveUserCake
    , serveUserStates
    , userIsInState
    , userIsReady
    , usersInStates
    )

where

import           Control.Monad.IO.Class
import           Data.Maybe
import           Data.Text (Text)
import qualified Data.Text           as T
import           Data.String (fromString)
import           Data.Time.Calendar (Day)
import qualified Data.ByteString.Char8 as BS
import qualified Data.Vector as V
import           Data.Aeson as Aeson
import qualified Data.HashMap.Strict as HashMap

import           Text.Printf

import           Database.PostgreSQL.Simple (query)
import           Database.PostgreSQL.Simple.SqlQQ.Alt

import           Snap
import           Snap.Snaplet.PostgresqlSimple hiding (query)

import Data.Model
import Data.Model.Patch     as Patch
import qualified Data.Model.Patch.Sql as Patch

import Carma.Model.Role      as Role
import Carma.Model.Usermeta  as Usermeta
import Carma.Model.UserState as UserState

import Application
import AppHandlers.Util
import Snaplet.Auth.PGUsers
import Snaplet.Search.Types (mkSel)

import Util
import Utils.LegacyModel (readIdent)


------------------------------------------------------------------------------
-- | Deny requests from unauthenticated users.
chkAuth :: AppHandler () -> AppHandler ()
chkAuth = chkAuthRoles alwaysPass


------------------------------------------------------------------------------
-- | Deny requests from unauthenticated or non-local users.
chkAuthLocal :: AppHandler () -> AppHandler ()
chkAuthLocal = chkAuthRoles (hasNoneOfRoles [Role.partner])


chkAuthAdmin :: AppHandler () -> AppHandler ()
chkAuthAdmin = chkAuthRoles (hasAnyOfRoles [Role.lovAdmin])


------------------------------------------------------------------------------
-- | Deny requests from unauthenticated or non-partner users.
--
-- Auth checker for partner screens
chkAuthPartner :: AppHandler () -> AppHandler ()
chkAuthPartner f =
  chkAuthRoles (hasAnyOfRoles [ Role.partner
                              , Role.head
                              , Role.supervisor]) f


------------------------------------------------------------------------------
-- | A predicate for a list of user roles.
type RoleChecker = [IdentI Role] -> Bool


------------------------------------------------------------------------------
-- | Produce a predicate which matches any list of roles
alwaysPass :: RoleChecker
alwaysPass = const True


hasAnyOfRoles :: [IdentI Role] -> RoleChecker
hasAnyOfRoles authRoles = any (`elem` authRoles)


hasNoneOfRoles :: [IdentI Role] -> RoleChecker
hasNoneOfRoles authRoles = all (not . (`elem` authRoles))


------------------------------------------------------------------------------
-- | Pass only requests from localhost users or non-localhost users
-- with a specific set of roles.
chkAuthRoles :: RoleChecker
             -- ^ Check succeeds if non-localhost user roles satisfy
             -- this predicate.
             -> AppHandler () -> AppHandler ()
chkAuthRoles roleCheck handler = do
  ipHeaderFilter
  req <- getRequest
  case rqRemoteAddr req /= rqLocalAddr req of
    False -> handler -- No checks for requests from localhost
    True  -> currentUserRoles >>= \case
      Nothing -> handleError 401
      Just roles ->
        if roleCheck roles
        then handler
        else handleError 401


-- | True if a user is in any of given states.
-- Nothing if we could not determine user's state due to his long inactivity
-- period.
userIsInState :: [UserStateVal] -> IdentI Usermeta -> AppHandler (Maybe Bool)
userIsInState uStates uid =
  liftPG $ \conn -> Patch.read uid conn >>=
  \case
    Left e -> error $
              "Could not fetch usermeta for user " ++ show uid ++
              ", error " ++ show e
    Right p -> do
      p' <- liftIO $ fillCurrentState p uid conn
      return
        $ (`elem` uStates)
        <$> Patch.get p' Usermeta.currentState


-- | True if a user is in @Ready@ state.
userIsReady :: IdentI Usermeta -> AppHandler Bool
userIsReady uid = fromMaybe False <$> userIsInState [Ready] uid


-- | Serve users with any of given roles in any of given states.
--
-- Response is a list of triples: @[["realName", "login", <id>],...]@
usersInStates :: [IdentI Role.Role] -> [UserStateVal] -> AppHandler ()
usersInStates roles uStates = do
  rows <- liftPG $ \c -> uncurry (query c) [sql|
   SELECT
   u.$(fieldPT Usermeta.realName)$,
   u.$(fieldPT Usermeta.login)$,
   u.$(fieldPT Usermeta.ident)$
   FROM $(tableQT Usermeta.ident)$ u
   LEFT JOIN (SELECT DISTINCT ON ($(fieldPT UserState.userId)$)
              $(fieldPT UserState.state)$, $(fieldPT UserState.userId)$
              FROM $(tableQT UserState.ident)$
              ORDER BY
              $(fieldPT UserState.userId)$,
              $(fieldPT UserState.ident)$ DESC) s
   ON u.$(fieldPT Usermeta.ident)$ = s.$(fieldPT UserState.userId)$
   WHERE s.$(fieldPT UserState.state)$ IN $(In uStates)$
   AND u.$(fieldPT Usermeta.roles)$ && ($(V.fromList roles)$)::int[];
   |]
  writeJSON (rows :: [(Text, Text, Int)])


-- | Serve user account data back to client.
serveUserCake :: AppHandler ()
serveUserCake = currentUserMeta >>= \case
  Nothing  -> handleError 401
  Just usr -> do
    let Just roles = V.toList <$> Patch.get usr Usermeta.roles
    let needCreatedServiceList = hasNoneOfRoles roles
          [Role.reportManager
          ,Role.supervisor
          ,Role.head
          ,Role.bo_qa
          ,Role.bo_director
          ,Role.bo_analyst
          ,Role.bo_bill
          ,Role.bo_close
          ,Role.bo_dealer
          ]
    case needCreatedServiceList of
      False -> writeJSON usr
      True  -> do
        let Just ident = Patch.get usr Usermeta.ident
        svcs <- liftPG $ \c -> uncurry (query c) [sql|
          select row_to_json(x) from
            (select
                extract(epoch from createtime) as ctime,
                s.parentid as "caseId",
                s.id as "svcId",
                t.label as "type"
              from servicetbl s join "ServiceType" t on (s.type = t.id)
              where status = 2
                and creator = $(ident)$
              order by createtime desc, parentid) x
          |]
        let list = toJSON (map fromOnly svcs :: [Aeson.Value])
        let Object usr' = Aeson.toJSON usr
        writeJSON $ Object
          $ HashMap.insert "_abandonedServices" list usr'


-- | Serve states for a user within a time interval.
serveUserStates :: AppHandler ()
serveUserStates = do
  usrId <- readUsermeta <$> getParamT "userId"
  from  <- readDay <$> getParam "from"
  to    <- readDay <$> getParam "to"
  states <- liftPG $ \c ->
    query c (fromString $ printf
      -- Get more then asked, we need this during drawing of timeline
      ("SELECT %s FROM \"UserState\" WHERE userId = ? " ++
       " AND ctime BETWEEN timestamp ? - interval '1 month' " ++
       "           AND     timestamp ? + interval '1 month' " ++
       " ORDER BY id ASC"
      )
      (T.unpack $ mkSel (undefined :: Patch UserState))) $
      (identVal usrId, from, to)
  writeJSON (states :: [Patch UserState])
  where
    readDay :: Maybe BS.ByteString -> Day
    readDay = read . BS.unpack . fromJust
    readUsermeta :: Maybe Text -> IdentI Usermeta
    readUsermeta = readIdent . fromJust
