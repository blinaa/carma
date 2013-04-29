#/ Transfrom model definitions into Backbone models, render model
#/ forms, template helpers.

# Backbonize a model
#
# @return Constructor of Backbone model
define [] , ->
  setReference = (parent, json, field, models) ->
    return json[field] = [] unless json[field]
    references = for m in json[field].split ','
      [name, id] = (v.trim() for v in m.split(':'))
      mkBb = backbonizeModel(models, name)
      new mkBb({id:id})
    # genRefAccessors(parent, field, references)
    json[field] = references

  backbonizeModel = (models, modelName, options) ->
    defaults         = {}
    fieldHash        = {}
    dictionaryFields = []
    dictManyFields   = []
    referenceFields  = []
    requiredFields   = []
    regexpFields     = []
    filesFields      = []
    jsonFields       = []
    dateTimeFields   = []
    distFields       = []
    groups           = []

    model = models[modelName]

    for f in model.fields
      if f.meta?
        requiredFields.push(f.name) if f.meta.required
        regexpFields.push(f.name)   if _.has(f.meta, "regexp")
        distFields.push(f.name)     if f.meta.distanceTo1? and f.meta.distanceTo2?

      fieldHash[f.name] = f
      defaults[f.name]  = null

      referenceFields.push(f.name)  if f.type == "reference"
      dictionaryFields.push(f.name) if f.type == "dictionary"
      dictManyFields.push(f.name)   if f.type == "dictionary-many"
      filesFields.push(f.name)      if f.type == "files"
      jsonFields.push(f.name)       if f.type == "json"
      dateTimeFields.push(f.name)   if f.type == "datetime"
      groups.push(f.groupName)      if f.groupName? and f.groupName not in groups

    M = Backbone.Model.extend
      defaults: defaults

      # Field caches

      # List of fields with dictionary type
      dictionaryFields: dictionaryFields
      dictManyFields: dictManyFields
      # List of field names which hold references to different
      # models.
      referenceFields: referenceFields
      # List of required fields
      requiredFields: requiredFields
      # List of fields with regexp checks
      regexpFields: regexpFields
      # List of files fields
      filesFields: filesFields
      dateTimeFields: dateTimeFields
      distFields: distFields
      # List of groups present in model
      groups: groups

          # Temporary storage for attributes queued for sending to
      # server.
      attributeQueue: {}
      # attributeQueue backuped before saving to server.
      # If save fails we merge new changes with backupped ones.
      # This prevents data loss in case of server failures.
      attributeQueueBackup: {}
      initialize: ->
        if not this.isNew() then this.fetch({ setBB: true })
        unless options?.bb?.manual_save? and options.bb.manual_save == true
          setTimeout((=> this.setupServerSync()), 1000)

      # Original definition
      #
      # This model and Backbone model (which is actually a
      # representation of instance of original model) are not to be
      # confused!
      model: model
      # Name of model definition
      name: modelName
      # Readable model title
      title: model.title
      # Hash of model fields as provided by model definition.
      fieldHash: fieldHash
      # Bind model changes to server sync
      setupServerSync: ->
        realUpdates = ->
              # Do not resave model when id is set after
              # first POST
              #
              # TODO Still PUT-backs
              this.save() unless this.hasChanged("id")
        this.bind("change", _.debounce(realUpdates, 1000), this)
      set: (key, val, options) ->
        attrs
        # we can get set(k,v,opts) or set(obj,opts)
        if _.isObject(key)
          attrs = key
          options = val
        else
          (attrs = {})[key] = val

        # Push new values in attributeQueue
        #
        # Never send "id", never send anything if user has no
        # canUpdate permission.
        #
        # Note that when model is first populated with data from
        # server, all attributes still make it to the queue,
        # resulting in full PUT-back upon first model "change"
        # event.
        #
        # TODO _.extend doesn't work here
        for k of attrs when k isnt 'id' and
            _.has(this.fieldHash, k)    and
            not _.isNull(attrs[k])
          # filter not changed attrs, so will do parent set
          if this.get(k) != attrs[k]
            this.attributeQueue[k] = attrs[k]

        Backbone.Model.prototype.set.call(this, attrs, options)

        # Do not send empty updates to server
      save: (attrs, options) ->
        # do not touch this timeout, dragons will eat you
        # also this will brake checkbox sync
        setTimeout( =>
          if not _.isEmpty(this.attributeQueue)
            options = if options then _.clone(options) else {}

            error = options.error
            options.error = (model, resp, options) ->
              _.isFunction(error) and error(model, resp, options)
              _.defaults(this.attributeQueue, this.attributeQueueBackup)

            Backbone.Model.prototype.save.call(this, attrs, options)
        , 100)

      # For checkbox fields, translate "0"/"1" to false/true
      # boolean.
      parse: (json) ->
        m = this.model;
        for k of json
          # TODO Perhaps inform client when unknown field occurs
          if (k isnt "id") and _.has(this.fieldHash, k)
            type = this.fieldHash[k].type
            if type.match(/^date/) and json[k].match(/\d+/)
              format = if type == "date"
                  "dd.MM.yyyy"
                else
                   "dd.MM.yyyy HH:mm"
              json[k] = new Date(json[k] * 1000).toString(format)
            if type == 'reference'
              setReference this, json, k, models
            else if type == "checkbox"
              json[k] = json[k] == "1"
            else if type == "json" and not _.isEmpty json[k]
              json[k] = JSON.parse json[k]
        return json

      toJSON: ->
        # Send only attributeQueue instead of the whole object
        json = _.clone(this.attributeQueue)
        this.attributeQueueBackup = _.clone(json)
        this.attributeQueue = {}
        for k of json
          if _.has(this.fieldHash, k)
            # serialize date field to unixtime (am I wrong?)
            if this.fieldHash[k].type.match(/^date/)
              date = Date.parseExact(
                json[k],
                ["dd.MM.yyyy HH:mm", "dd.MM.yyyy"])
              if date
                timestamp = Math.round(date.getTime() / 1000)
                json[k] = String(timestamp)
            # serialize references to name1:id1,name2:id2,... string
            if this.fieldHash[k].type == 'reference'
              json[k] = ("#{r.name}:#{r.id}" for r in json[k]).join(',')
            if this.fieldHash[k].type == 'json'
              json[k] = JSON.stringify json[k]
          # Map boolean values to string "0"/"1"'s for server
          # compatibility
          if _.isBoolean(json[k])
            json[k] = String(if json[k] then "1" else "0")
        return json

      urlRoot: "/_/" + modelName

      fetch: (options) ->
        # we need our own fetch, so we can use bb set instead
        # of ours to keep attributeQueue empty after first fetch
        options = if options then _.clone(options) else {}
        success = options.success
        setf = if options.setBB
            Backbone.Model.prototype.set #.call(this, attrs, options)
          else this.set
        options.success = (resp, status, xhr) =>
          return false unless setf.call(this, this.parse(resp, xhr), options)
          success(this, resp, options) if success
        return Backbone.sync('read', this, options)

    return M

  { backbonizeModel: backbonizeModel }
