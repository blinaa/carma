define [], ->
  # This module maps server <-> client data types
  # c2s prefix means client  -> server
  # s2c prefix means client <-  server

  c2sDate = (fmt) -> (v) ->
    date = Date.parseExact(v, fmt)
    if date
      String(Math.round(date.getTime() / 1000))
    else
      # FIXME: really what should this do with wrong dates?
      console.error("datamap: can't parse date '#{v}' with '#{fmt}'")
      ""

  iso8601date = "yyyy-MM-dd"

  c2sDay = (fmt) -> (v) ->
    date = Date.parseExact(v, fmt)
    if date
      date.toString(iso8601date)
    else
      console.error("datamap: can't parse date '#{v}' in ISO-8601")

  s2cDate = (fmt) -> (v) ->
    return null if _.isEmpty v
    d = undefined
    d = new Date(v * 1000)
    return d.toString(fmt) if isFinite d
    d = Date.parseExact(v, "yyyy-MM-dd HH:mm:ssz")
    return d.toString(fmt) if not _.isNull(d) && isFinite d

  s2cDay = (fmt) -> (v) ->
    return null if _.isEmpty v
    new Date.parseExact(v, iso8601date).toString(fmt)

  s2cJson = (v) ->
    return null if _.isEmpty v
    JSON.parse(v)

  c2sDictSet = (v) ->
    vals = v.split(',')
    ids = _.map vals, (v) -> parseInt v
    # check type of keys, we have in dict, it may be Text or Int
    if _.all ids, _.isNaN
      vals
    else
      ids

  c2sTypes =
    'dictionary-set': c2sDictSet
    checkbox  : (v) -> if v then "1" else "0"
    Bool      : (v) -> v
    Integer   : (v) -> parseInt v
    Double    : (v) -> parseFloat v.replace ',', '.'
    Day       : c2sDay("dd.MM.yyyy")
    dictionary: (v) -> if _.isNull v then '' else v
    date      : c2sDate("dd.MM.yyyy")
    datetime  : c2sDate("dd.MM.yyyy HH:mm")
    json      : JSON.stringify
    ident     : (v) -> parseInt v
    'interval-datetime': (v) ->
      v.map (t) -> Date.parseExact(t, "dd.MM.yyyy")?.toString "yyyy-MM-ddTHH:mm:ss.0Z"

  s2cTypes =
    'dictionary-set': (v) -> v.join(',')
    checkbox  : (v) -> v == "1"
    Bool      : (v) -> v
    Integer   : (v) -> v
    Double    : (v) -> v
    Day       : s2cDay("dd.MM.yyyy")
    dictionary: (v) -> v
    date      : s2cDate("dd.MM.yyyy")
    datetime  : s2cDate("dd.MM.yyyy HH:mm")
    json      : s2cJson
    'interval-date': (v) -> v

  defaultc2s = (v) -> if _.isNull(v) then "" else String(v)
  c2s = (val, type) -> (c2sTypes[type] || defaultc2s)(val)
  s2c = (val, type) -> (s2cTypes[type] || _.identity)(val)

  mapObj = (mapper) -> (obj, types) ->
    r = {}
    r[k] = mapper(v, types[k]) for k, v of obj
    r

  modelTypes = (model) -> _.foldl model.fields, ((m, f) -> m[f.name] = f.type; m), {}

  class Mapper
    constructor: (model) ->
      @types = modelTypes(model)

    c2sObj: (obj) => mapObj(c2s)(obj, @types)
    s2cObj: (obj) => mapObj(s2c)(obj, @types)

  c2s    : c2s
  s2c    : s2c
  c2sObj : mapObj(c2s)
  s2cObj : mapObj(s2c)
  Mapper : Mapper
