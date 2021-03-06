{_: {pick, memoize}, Immutable: {Record, List}} = require "carma/vendor"


class CaseHistoryAnswersItem extends Record(
  # scalar types
  nextSlide : 0
  header    : ""
  text      : ""
  file      : null # null or string
  mediaType : "image"

  # unknown types
  # action    : {}
)
  @plainObjScalarProps: ["nextSlide", "header", "text"]
  @fromPlain: (plainObj) =>
    x = pick plainObj, @plainObjScalarProps
    { attachment } = plainObj

    x.file =
      if attachment
        "/s/fileupload/attachment/#{attachment.id}/#{attachment.filename}"
      else if plainObj.file
        plainObj.file

    mediaType = attachment?.mediaType
    x.mediaType = mediaType if mediaType?
    new @ x


class CaseHistoryAnswersList extends List
  @Item: CaseHistoryAnswersItem
  @fromPlain: (plainArr) => new @ plainArr.map (x) => @Item.fromPlain x
  constructor: (args...) -> return super args...


class CaseHistoryActionsItem extends Record(
  # scalar types
  label : ""
  svc   : "" # Service model name
)
  @plainObjScalarProps: ["label", "svc"]
  @fromPlain: (plainObj) => new @ pick plainObj, @plainObjScalarProps


class CaseHistoryActionsList extends List
  @Item: CaseHistoryActionsItem
  @fromPlain: (plainArr) => new @ plainArr.map (x) => @Item.fromPlain x
  constructor: (args...) -> return super args...


class CaseHistoryResourcesItem extends Record(
  # scalar types
  file      : ""
  text      : ""
  mediaType : "image"
)
  @plainObjScalarProps: ["text"]
  @fromPlain: (plainObj) =>
    x = pick plainObj, @plainObjScalarProps
    { attachment } = plainObj

    x.file =
      if attachment
        "/s/fileupload/attachment/#{attachment.id}/#{attachment.filename}"
      else
        plainObj.file

    mediaType = attachment?.mediaType
    x.mediaType = mediaType if mediaType?
    new @ x


class CaseHistoryResourcesList extends List
  @Item: CaseHistoryResourcesItem
  @fromPlain: (plainArr) => new @ plainArr.map (x) => @Item.fromPlain x
  constructor: (args...) -> return super args...


class CaseHistoryItem extends Record(
  # scalar types
  id           : 0
  header       : ""
  body         : ""   # html code
  answerIx     : null # number - selected answer index
  answeredBy   : null # string
  answerTime   : null # string
  deprecatedBy : null # number

  # complex types
  answers      : new CaseHistoryAnswersList
  actions      : new CaseHistoryActionsList
  resources    : new CaseHistoryResourcesList
)
  @plainObjScalarProps: [
    "id", "header", "body"
    "answerIx", "answeredBy", "answerTime"
    "deprecatedBy"
  ]

  @fromPlain: (plainObj) =>
    obj = pick plainObj, @plainObjScalarProps
    new @ Object.assign obj,
      answers   : CaseHistoryAnswersList.fromPlain plainObj.answers
      actions   : CaseHistoryActionsList.fromPlain plainObj.actions
      resources : CaseHistoryResourcesList.fromPlain plainObj.resources


class CaseHistoryList extends List
  @Item: CaseHistoryItem
  @fromPlain: (plainArr) => new @ plainArr.map (x) => @Item.fromPlain x
  onlyNotDeprecated: -> @filter (x) -> x.get("deprecatedBy") is null
  getPreviousById: (id) -> @filter (x) -> x.get("deprecatedBy") is id

  constructor: (args...) ->
    list = super args...
    list.onlyNotDeprecated = memoize @onlyNotDeprecated
    list.getPreviousById = memoize @getPreviousById
    return list


module.exports = {
  CaseHistoryList
  CaseHistoryItem
}
