class CTI
  constructor: (@extension) ->
    console.log "Enabling CTI for extension #{extension}"

    if global.config("csta-ws-host")?
      host = global.config("csta-ws-host")
    else
      host = location.hostname

    port = global.config("csta-ws-port")

    if window.location.protocol == "https:"
      url = "wss://#{host}:#{port}/#{extension}"
    else
      url = "ws://#{host}:#{port}/#{extension}"

    # List of WS message subscribers
    @subscribers = []

    @ws = new WebSocket(url)
    @ws.onconnect =
    @ws.onmessage = (raw) =>
      msg = JSON.parse raw.data
      _.each @subscribers, (h) -> h msg

  subscribe: (handler) ->
    @subscribers.push handler

  makeCall: (number) ->
    @ws.send JSON.stringify
      action: "MakeCall"
      number: parseInt number

  endCall: (callId) ->
    @ws.send JSON.stringify
      action: "EndCall"
      callId: callId

  holdCall: (callId) ->
    @ws.send JSON.stringify
      action: "HoldCall"
      callId: callId

  retrieveCall: (callId) ->
    @ws.send JSON.stringify
      action: "RetrieveCall"
      callId: callId

  answerCall: (callId) ->
    @ws.send JSON.stringify
      action: "AnswerCall"
      callId: callId

  sendDigits: (callId, digits) ->
    @ws.send JSON.stringify
      action: "SendDigits"
      callId: callId
      digits: digits

class CTIPanel
  constructor: (cti, el) ->
    # CTI panel state (it's a bit different from agent state in CSTA
    # lib to make interface coding easier)
    kvm =
      calls: ko.observableArray []
      # CallId to extension mapping (used to keep extension number
      # values between state changes)
      extensions: {}

    displayedToInternal = (number) ->
      number.replace("+7", "98").replace("+", "9810")

    internalToDisplayed = (number) ->
      number?.match(/\d+/)?[0]?.replace(/^(98|8|)(\d{10})$/, "\+7$2")

    # Update kvm from state reported by the service
    stateToVM = (state) ->
      # VM for a call. If callId is null, return fresh VM for empty
      # CTI panel
      callToVM = (call, callId) ->
        number     : ko.observable internalToDisplayed call.interlocutor
        callStart  : ko.observable call.start?
        callId     : callId
        extension  : ko.computed
          write:
            (v) ->
              # Send only new digits to csta-ws
              old = kvm.extensions[callId] || ""
              kvm.extensions[callId] = v
              if v.length > old.length
                diff = v.length - old.length
                cti.sendDigits callId, v.substr(old.length, diff)
          read:
            -> kvm.extensions[callId] || ""

        # canX are observable, because we want to hide buttons from
        # the panel even before the service reports new call
        # state/event
        canExtend  : ko.observable(
          call.answered? && call.direction == "Out" && !call.held)
        canCall    : ko.observable !(callId?)
        canAnswer  : ko.observable (!(call.answered?) && (call.direction == "In"))
        canHold    : ko.observable (call.answered? && !call.held)
        canRetrieve: ko.observable call.held
        canEnd     : ko.observable(
          !call.held && (call.answered? || (call.direction == "Out")))

        # Button click handlers
        makeThis: ->
          return if _.isEmpty @number()
          cti.makeCall displayedToInternal @number()
          @canCall false
          @callStart new Date().toISOString()
        answerThis: ->
          cti.answerCall callId
          @canAnswer false
        endThis: ->
          cti.endCall callId
          @canEnd false
        holdThis: ->
          cti.holdCall callId
        retrieveThis: ->
          cti.retrieveCall callId


      newCalls = if _.isEmpty state.calls
        [callToVM {}, null]
      else
        for callId, call of state.calls
          callToVM call, callId

      # Delete unknown extension digits
      for k in _.keys kvm.extensions
        if !_.contains(_.keys(state.calls), k)
          delete kvm.extensions[k]

      kvm.calls.removeAll()
      for c in newCalls
        kvm.calls.push c

    wsHandler = (msg) ->
      if msg.calls?
        stateToVM msg

      if msg.newState?
        stateToVM msg.newState

    cti.subscribe wsHandler

    el.show()
    ko.applyBindings kvm, el[0]

    # Allow only 0-9, * and # in extension number field
    $(el).on "keydown", ".extension-mask", (e) ->
      unless ((e.which >= 48 && e.which <= 57) ||
        (e.which >= 96 && e.which <= 105) ||
          e.which == 106 || e.which == 56 || e.which == 51)
        e.preventDefault()

    $(document).keydown (e) ->
      if e.which == 192
        el.toggle()
