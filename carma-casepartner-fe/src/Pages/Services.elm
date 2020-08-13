module Pages.Services exposing (Flags, Model, Msg, page)

import Api
import Bootstrap.Button as Button
import Bootstrap.ButtonGroup as ButtonGroup
import Bootstrap.Dropdown as Dropdown
import Bootstrap.Grid as Grid
import Bootstrap.Grid.Col as Col
import Bootstrap.Grid.Row as Row
import Bootstrap.Navbar as Navbar
import Bootstrap.Table as Table
import Bootstrap.Text as Text
import Bootstrap.Utilities.Flex as Flex
import Bootstrap.Utilities.Spacing as Spacing
import Generated.Route as Route
import Global
import Html
    exposing
        ( Html
        , br
        , div
        , h3
        , text
        )
import Html.Attributes
    exposing
        ( attribute
        , class
        , style
        )
import Html.Events exposing (onClick)
import Http
import MessageToast exposing (MessageToast)
import Page exposing (Document, Page)
import Task
import Time
import Types exposing (ClosingCaseInfo, CurrentCaseInfo)
import Ui


{-| seconds between updates
-}
updateSeconds : Float
updateSeconds =
    60


pageSize : Int
pageSize =
    10


spinnerSize : String
spinnerSize =
    "10rem"


type alias Flags =
    ()


type alias Model =
    { currentCases : List CurrentCaseInfo
    , currentCasesPage : Int
    , showCurrentSpinner : Bool
    , closingCases : List ClosingCaseInfo
    , closingCasesPage : Int
    , showClosingSpinner : Bool
    , navbarState : Navbar.State
    , usermenuState : Dropdown.State
    , nowMillis : Int
    , messageToast : MessageToast Msg
    }


type CasesType
    = Current
    | Closing


type Msg
    = CurrentCase Int
    | ClosingCase Int
    | SearchCases
    | GetCurrentCases (Result Http.Error (List CurrentCaseInfo))
    | GetClosingCases (Result Http.Error (List ClosingCaseInfo))
    | CasesPrevPage CasesType
    | CasesNextPage CasesType
    | NavbarMsg Navbar.State
    | UsermenuMsg Dropdown.State
    | Logout
    | NowTime Time.Posix
    | Tick Time.Posix
    | UpdateCustomMessageToast (MessageToast Msg)


page : Page Flags Model Msg
page =
    Page.component
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


init : Global.Model -> Flags -> ( Model, Cmd Msg, Cmd Global.Msg )
init _ _ =
    let
        ( navbarState, navbarCmd ) =
            Navbar.initialState NavbarMsg
    in
    ( { currentCases = []
      , currentCasesPage = 1
      , showCurrentSpinner = True
      , closingCases = []
      , closingCasesPage = 1
      , showClosingSpinner = True
      , navbarState = navbarState
      , usermenuState = Dropdown.initialState
      , nowMillis = 0
      , messageToast =
            MessageToast.initWithConfig UpdateCustomMessageToast
                { delayInMs = 2000
                , toastsToShow = 10
                }
      }
    , navbarCmd
    , Cmd.none
    )


update : Global.Model -> Msg -> Model -> ( Model, Cmd Msg, Cmd Global.Msg )
update _ msg model =
    case msg of
        CurrentCase serviceId ->
            ( model
            , Cmd.none
            , Cmd.batch
                [ Global.serviceId serviceId
                , Global.navigate Route.ShowService
                ]
            )

        ClosingCase serviceId ->
            ( model
            , Cmd.none
            , Cmd.batch
                [ Global.serviceId serviceId
                , Global.navigate Route.ShowService
                ]
            )

        SearchCases ->
            ( model
            , Cmd.none
            , Global.navigate Route.SearchCases
            )

        GetCurrentCases result ->
            case result of
                Err _ ->
                    let
                        messageToast =
                            model.messageToast
                                |> MessageToast.danger
                                |> MessageToast.withMessage "Error get current latest cases "
                    in
                    ( { model
                        | showCurrentSpinner = False
                        , messageToast = messageToast
                      }
                    , Cmd.none
                    , Cmd.none
                    )

                Ok currentCases ->
                    ( { model
                        | currentCases = currentCases
                        , currentCasesPage = 1
                        , showCurrentSpinner = False
                        , closingCases = []
                        , closingCasesPage = 1
                        , showClosingSpinner = True
                      }
                    , Api.getLatestClosingCases GetClosingCases
                    , Cmd.none
                    )

        GetClosingCases result ->
            case result of
                Err _ ->
                    let
                        messageToast =
                            model.messageToast
                                |> MessageToast.danger
                                |> MessageToast.withMessage "Error get closing latest cases "
                    in
                    ( { model | showClosingSpinner = False, messageToast = messageToast }
                    , Cmd.none
                    , Cmd.none
                    )

                Ok closingCases ->
                    ( { model
                        | closingCases = closingCases
                        , closingCasesPage = 1
                        , showClosingSpinner = False
                      }
                    , Task.perform NowTime Time.now
                    , Cmd.none
                    )

        CasesPrevPage t ->
            case t of
                Current ->
                    let
                        currentCasesPage =
                            if model.currentCasesPage > 1 then
                                model.currentCasesPage - 1

                            else
                                1
                    in
                    ( { model
                        | currentCasesPage = currentCasesPage
                      }
                    , Cmd.none
                    , Cmd.none
                    )

                Closing ->
                    let
                        closingCasesPage =
                            if model.closingCasesPage > 1 then
                                model.closingCasesPage - 1

                            else
                                1
                    in
                    ( { model
                        | closingCasesPage = closingCasesPage
                      }
                    , Cmd.none
                    , Cmd.none
                    )

        CasesNextPage t ->
            case t of
                Current ->
                    let
                        currentCasesPage =
                            if
                                model.currentCasesPage
                                    < ceiling
                                        (toFloat (List.length model.currentCases)
                                            / toFloat pageSize
                                        )
                            then
                                model.currentCasesPage + 1

                            else
                                model.currentCasesPage
                    in
                    ( { model
                        | currentCasesPage = currentCasesPage
                      }
                    , Cmd.none
                    , Cmd.none
                    )

                Closing ->
                    let
                        closingCasesPage =
                            if
                                model.closingCasesPage
                                    < ceiling
                                        (toFloat (List.length model.closingCases)
                                            / toFloat pageSize
                                        )
                            then
                                model.closingCasesPage + 1

                            else
                                model.closingCasesPage
                    in
                    ( { model
                        | closingCasesPage = closingCasesPage
                      }
                    , Cmd.none
                    , Cmd.none
                    )

        NavbarMsg state ->
            ( { model | navbarState = state }
            , Api.getLatestCurrentCases GetCurrentCases
            , Cmd.none
            )

        UsermenuMsg state ->
            ( { model | usermenuState = state }
            , Cmd.none
            , Cmd.none
            )

        Logout ->
            ( model
            , Cmd.none
            , Global.logout
            )

        NowTime newTime ->
            ( { model
                | nowMillis = Time.posixToMillis newTime
              }
            , Cmd.none
            , Cmd.none
            )

        Tick _ ->
            ( { model
                | currentCases = []
                , currentCasesPage = 1
                , showCurrentSpinner = True
              }
            , Api.getLatestCurrentCases GetCurrentCases
            , Cmd.none
            )

        UpdateCustomMessageToast updatedMessageToast ->
            ( { model | messageToast = updatedMessageToast }
            , Cmd.none
            , Cmd.none
            )


subscriptions : Global.Model -> Model -> Sub Msg
subscriptions _ model =
    Sub.batch
        [ Time.every (updateSeconds * 1000) Tick
        , Dropdown.subscriptions model.usermenuState UsermenuMsg
        ]


view : Global.Model -> Model -> Document Msg
view global model =
    { title = "Текущие заявки"
    , body =
        [ Ui.page
            { navbarMsg = NavbarMsg
            , logoutMsg = Logout
            , usermenuMsg = UsermenuMsg
            , navbarState = model.navbarState
            , usermenuState = model.usermenuState
            , username = global.username
            , buttons =
                [ ( True, NavbarMsg model.navbarState, "Текущие заявки" )
                , ( False, SearchCases, "Поиск заявок" )
                ]
            }
          <|
            div []
                [ viewCurrentCases model
                , br [] []
                , viewClosingCases model
                , br [] []
                , div []
                    [ model.messageToast
                        |> MessageToast.overwriteContainerAttributes
                            [ style "top" "20px"
                            , style "bottom" "auto"
                            , style "right" "20px"
                            ]
                        |> MessageToast.view
                    ]
                ]
        ]
    }


viewCasesTitle : String -> String -> CasesType -> Html Msg
viewCasesTitle title pageNumber caseType =
    Grid.row [ Row.attrs [ Spacing.p1, Flex.row ] ]
        [ Grid.col [ Col.md6, Col.orderMd1, Col.orderLg3, Col.attrs [ Flex.alignSelfCenter ] ]
            [ h3 [ style "margin" "0 0 0 0" ] [ text title ] ]
        , Grid.col [ Col.sm2, Col.attrs [ Spacing.p1, Spacing.pl3 ] ]
            [ ButtonGroup.buttonGroup []
                [ ButtonGroup.button
                    [ Button.primary
                    , Button.attrs [ onClick <| CasesPrevPage caseType ]
                    ]
                    [ text "<" ]
                , ButtonGroup.button
                    [ Button.primary ]
                    [ text pageNumber ]
                , ButtonGroup.button
                    [ Button.primary
                    , Button.attrs [ onClick <| CasesNextPage caseType ]
                    ]
                    [ text ">" ]
                ]
            ]
        ]


casesTableAttrs : List (Table.TableOption msg)
casesTableAttrs =
    [ Table.bordered
    , Table.striped
    , Table.small
    , Table.responsiveLg
    , Table.attr (style "background-color" Ui.colors.casesBg)
    ]


hC =
    Table.cellAttr <| class "text-center"


vC =
    Table.cellAttr <| class "align-middle"


thW w =
    Table.cellAttr <| attribute "width" (String.fromInt w ++ "%")


cellAttrDanger =
    Table.cellAttr <| class "table-danger"


cellAttrWarning =
    Table.cellAttr <| class "table-warning"


cellAttrSuccess =
    Table.cellAttr <| class "table-success"


cellAttrInfo =
    Table.cellAttr <| class "table-info"


colorOfPay : String -> List (Table.CellOption msg)
colorOfPay payType =
    case payType of
        "Клиент" ->
            [ cellAttrWarning ]

        "Смешанный" ->
            [ cellAttrWarning ]

        _ ->
            []


hideMobile =
    Table.cellAttr <| class "d-none d-md-table-cell"


viewCurrentCases : Model -> Html Msg
viewCurrentCases model =
    let
        formatAccordTime : String -> String
        formatAccordTime t =
            case parseTime t of
                Just ( 0, hours, minutes ) ->
                    String.fromInt hours ++ ":" ++ String.fromInt minutes

                Just ( days, hours, minutes ) ->
                    String.fromInt days
                        ++ " дн. "
                        ++ String.fromInt hours
                        ++ ":"
                        ++ String.fromInt minutes

                Nothing ->
                    t

        {- Returns: (Days, Hours, Minutes) -}
        parseTime : String -> Maybe ( Int, Int, Int )
        parseTime t =
            case String.split " " t of
                [ d, h, m ] ->
                    case List.map String.toInt [ d, h, m ] of
                        [ Just days, Just hours, Just minutes ] ->
                            if days >= 0 && hours >= 0 && (minutes >= 0 && minutes < 60) then
                                Just ( days, hours, minutes )

                            else
                                Nothing

                        _ ->
                            Nothing

                _ ->
                    Nothing

        colorOfTimer : String -> List (Table.CellOption msg)
        colorOfTimer accordTime =
            if accordTime == "В работе" then
                []

            else if accordTime == "Опоздание" then
                [ cellAttrDanger ]

            else
                case parseTime accordTime of
                    Just ( days, hours, minutes ) ->
                        if days == 0 && hours == 0 && minutes <= 5 then
                            [ cellAttrWarning ]

                        else
                            [ cellAttrSuccess ]

                    Nothing ->
                        [ Table.cellInfo ]
    in
    Grid.row [] <|
        if model.showCurrentSpinner then
            [ Grid.col [ Col.textAlign Text.alignXsCenter ]
                [ Ui.viewSpinner spinnerSize ]
            ]

        else
            [ Grid.col []
                [ viewCasesTitle "Текущие заявки"
                    (String.fromInt model.currentCasesPage
                        ++ "/"
                        ++ String.fromInt
                            (ceiling
                                (toFloat (List.length model.currentCases)
                                    / toFloat pageSize
                                )
                            )
                    )
                    Current
                , Table.table
                    { options = casesTableAttrs
                    , thead =
                        let
                            ha =
                                [ hC, vC ]
                        in
                        Table.simpleThead
                            [ Table.th ha [ text "Заявка" ]
                            , Table.th ha [ text "Дата подачи" ]
                            , Table.th ha [ text "Услуга" ]
                            , Table.th (hideMobile :: ha) [ text "Статус" ]
                            , Table.th ha [ text "Остаток времени" ]
                            , Table.th (hideMobile :: ha) [ text "Марка/Модель" ]
                            , Table.th (hideMobile :: ha) [ text "Адрес места поломки" ]
                            , Table.th ha [ text "Тип оплаты" ]
                            ]
                    , tbody =
                        Table.tbody [] <|
                            List.map (Table.tr []) <|
                                List.map
                                    (\theCase ->
                                        [ Table.td [ hC, vC, thW 3 ]
                                            [ Ui.idCell CurrentCase
                                                theCase.cuServiceId
                                                theCase.cuCaseId
                                                theCase.cuServiceSerial
                                            ]
                                        , Table.td [ hC, vC, thW 5 ] [ Ui.timeCell theCase.cuCallDate ]
                                        , Table.td [ hC, vC, thW 10 ] [ Ui.cell theCase.cuTypeOfService ]
                                        , Table.td [ hideMobile, hC, vC, thW 5 ] [ Ui.cell theCase.cuStatus ]
                                        , Table.td
                                            (colorOfTimer theCase.cuAccordTime
                                                ++ [ hC, vC, thW 5 ]
                                            )
                                            [ Ui.cell <| formatAccordTime theCase.cuAccordTime ]
                                        , Table.td [ hideMobile, hC, vC, thW 10 ] [ Ui.cell theCase.cuMakeModel ]
                                        , Table.td [ hideMobile, vC ] [ Ui.addressCell theCase.cuBreakdownPlace ]
                                        , Table.td
                                            (colorOfPay theCase.cuPayType
                                                ++ [ hC, vC, thW 10 ]
                                            )
                                            [ Ui.cell theCase.cuPayType ]
                                        ]
                                    )
                                    (model.currentCases
                                        |> List.drop ((model.currentCasesPage - 1) * pageSize)
                                        |> List.take pageSize
                                    )
                    }
                ]
            ]


viewClosingCases : Model -> Html Msg
viewClosingCases model =
    Grid.row [] <|
        if model.showClosingSpinner then
            [ Grid.col [ Col.textAlign Text.alignXsCenter ] <|
                [ Ui.viewSpinner spinnerSize ]
            ]

        else
            [ Grid.col []
                [ viewCasesTitle "Закрытие заявок"
                    (String.fromInt model.closingCasesPage
                        ++ "/"
                        ++ String.fromInt (ceiling (toFloat (List.length model.closingCases) / toFloat pageSize))
                    )
                    Closing
                , Table.table
                    { options = casesTableAttrs
                    , thead =
                        let
                            ha =
                                [ hC, vC ]
                        in
                        Table.simpleThead
                            [ Table.th ha [ text "Заявка" ]
                            , Table.th ha [ text "Дата подачи" ]
                            , Table.th ha [ text "Услуга" ]
                            , Table.th ha [ text "Марка/Модель" ]
                            , Table.th (hideMobile :: ha) [ text "Адрес места поломки" ]
                            , Table.th ha [ text "Тип оплаты" ]
                            ]
                    , tbody =
                        Table.tbody [] <|
                            List.map (Table.tr []) <|
                                List.map
                                    (\theCase ->
                                        [ Table.td [ hC, vC, thW 3 ]
                                            [ Ui.idCell CurrentCase
                                                theCase.clServiceId
                                                theCase.clCaseId
                                                theCase.clServiceSerial
                                            ]
                                        , Table.td [ hC, vC, thW 5 ] [ Ui.dateCell theCase.clCallDate ]
                                        , Table.td [ hC, vC, thW 10 ] [ Ui.cell theCase.clTypeOfService ]
                                        , Table.td [ hC, vC, thW 15 ] [ Ui.cell theCase.clMakeModel ]
                                        , Table.td [ hideMobile, vC ] [ Ui.addressCell theCase.clBreakdownPlace ]
                                        , Table.td
                                            (colorOfPay theCase.clPayType
                                                ++ [ hC, vC, thW 10 ]
                                            )
                                            [ Ui.cell theCase.clPayType ]
                                        ]
                                    )
                                    (model.closingCases
                                        |> List.drop ((model.closingCasesPage - 1) * pageSize)
                                        |> List.take pageSize
                                    )
                    }
                ]
            ]