# TODO Use city in geocoding routines!

# Default marker icon size
this.iconSize = new OpenLayers.Size(50, 50)


# Default map zoom level
this.zoomLevel = 16


this.nominatimRevQuery =
  "http://nominatim.openstreetmap.org/reverse.php?format=json&accept-language=ru-RU,ru&"


this.nominatimQuery =
  "http://nominatim.openstreetmap.org/search?format=json&accept-language=ru-RU,ru&q="


this.wsgProj = new OpenLayers.Projection("EPSG:4326")

this.osmProj = new OpenLayers.Projection("EPSG:900913")


# Build readable address from reverse Nominatim JSON response
this.buildReverseAddress = (res) ->
  if (res.error)
    return null
    
  addr = (res.address.road || res.address.pedestrian)

  if (_.isUndefined(res.address.house_number))
    return addr
  else
    return addr +  ", " + res.address.house_number


# Erase existing marker layer and install a new one of the same name
this.reinstallMarkers = (osmap, layerName) ->
  layers = osmap.getLayersByName(layerName)
  if (!_.isEmpty(layers))
    osmap.removeLayer(layers[0])
  new_layer = new OpenLayers.Layer.Markers(layerName)
  osmap.addLayer(new_layer)

  return new_layer

# Setup OpenLayers map
#
# Template for OL placeholder may specify HTML5 attributes:
#
# - data-target-addr: if set, map will be clickable, enabled for
#                     reverse geocoding (clicking the map will write
#                     geocoding address to this field on `case` model)
#
# - data-target-coords: read initial position & blip from this field
#                       of `case`, write geocoding results here (if
#                       it's enabled)
#
# TODO Hardcoded `case` view is used for address and coordinates
# fields, even if the map itself is in a different view.
this.initOSM = (el, table) ->
  return if $(el).hasClass("olMap")

  fieldName = $(el).attr("name")
  view = elementView($(el))
  modelName = elementModel($(el))

  osmap = new OpenLayers.Map(el.id)
  osmap.addLayer(new OpenLayers.Layer.OSM())
  
  # Default location
  osmap.setCenter(new OpenLayers.LonLat(37.617874,55.757549)
                  .transform(wsgProj, osmProj),
                  zoomLevel)


  coord_field = modelField(modelName, fieldName).meta["targetCoords"]
  addr_field = modelField(modelName, fieldName).meta["targetAddr"]


  # Place a blip and recenter if coordinates are already known
  if coord_field?
    # TODO Drop hardcoded name of the case view (case-form)
    coords = global.viewsWare['case-form'].knockVM[coord_field]()
    if coords?
      coords = lonlatFromShortString(coords)
      osmap.setCenter(coords.transform(wsgProj, osmProj), zoomLevel)
      carBlip(osmap, coords)

  # Setup handler if map is clickable
  if addr_field?
    osmap.events.register("click", osmap, (e) ->
      coords = osmap.getLonLatFromViewPortPx(e.xy)
               .transform(osmProj, wsgProj)

      if coord_field?
        global.viewsWare['case-form']
        .knockVM[coord_field](coords.toShortString())

      $.getJSON(nominatimRevQuery + "lon=#{coords.lon}&lat=#{coords.lat}",
      (res) ->
        addr = buildReverseAddress(res)

        global.viewsWare['case-form'].knockVM[addr_field](addr)

        carBlip(osmap, osmap.getLonLatFromViewPortPx(e.xy))
      )
    )

  partner_field = modelField(modelName, fieldName).meta["targetPartner"]
  partnerAddr_field = modelField(modelName, fieldName).meta["targetPartnerId"]
  table_field = modelField(modelName, fieldName).meta["partnerTable"]
  table = view.find("table##{table_field}")

  if partner_field?
    # Redraw partner blips on map when dragging or zooming
    osmap.events.register("moveend", osmap, (e) ->
      # Calculate new bounding box
      bounds = osmap.getExtent()
      pts = bounds.toArray()
      a = new OpenLayers.LonLat(pts[0], pts[1])
      b = new OpenLayers.LonLat(pts[2], pts[3])
      a.transform(osmProj, wsgProj)
      b.transform(osmProj, wsgProj)
      $.getJSON("/geo/partners/#{a.lon},#{a.lat}/#{b.lon},#{b.lat}/", (pres) ->
        partnerBlips(
          osmap, pres, table.data("cache"), view,
          partner_field, partnerAddr_field))
    )

  $(el).data("osmap", osmap)


# Move the car crash blip on the map
this.carBlip = (osmap, coords) ->
  ico = new OpenLayers.Icon("/s/img/car-icon.png", iconSize)
  markers = reinstallMarkers(osmap, "Car")
  markers.addMarker(
    new OpenLayers.Marker(coords, ico))


# Render list of partner markers on the map
#
# Arguments:
# 
# - osmap: map to render on
# 
# - partners: a list of [id, lon, lat] triples
#
# - tableCache: a hash of all partners, where key is id and value is
#               an object with fields "name", "addrDeFacto", "phone1",
#               "workingTime"
#
# - view
#
# - partnerField: clicking a button in marker popup will set this
#                 value in given view to partner name
#
# - partnerAddr: same as partnerField, but for partner address
this.partnerBlips = (osmap, partners, tableCache, view, partnerField, partnerAddr) ->
  markers = do (osmap) -> reinstallMarkers(osmap, "Partners")
  tpl = $("#partner-popup-template").html()
  for blip in partners
    do (blip) ->
      # Skip partners not in table
      return if not tableCache[blip[0]]
      
      partner = tableCache[blip[0]]
      coords = new OpenLayers.LonLat(blip[1], blip[2])
                   .transform(wsgProj, osmProj)

      mrk = new OpenLayers.Marker(
          coords, new OpenLayers.Icon("/s/img/tow-icon.png", iconSize))

      # Show partner info from table cache when clicking marker
      mrk.events.register("click", mrk, (e) ->
        popup = new OpenLayers.Popup.FramedCloud(
          partner.id, mrk.lonlat,
          new OpenLayers.Size(200, 200),
          Mustache.render(tpl, partner),
          null, true)
        osmap.addPopup(popup))
      markers.addMarker(mrk)


# Read "32.54, 56.21" (the way coordinates are stored in model fields)
# into LonLat object
this.lonlatFromShortString = (coords) ->
  parts = coords.split(", ")
  return new OpenLayers.LonLat(parts[0], parts[1])


# Forward geocoding picker (address -> coordinates)
#
# For field with this picker type, following metas are recognized:
#
# - targetMap: name of map field to write geocoding results into
#              (recenter & set new blip on map)
#
# - targetCoords: name of field to write geocoding results into
#                 (coordinates in "lon, lat" format). If this meta is
#                 set, map will be recenter upon map setup using value
#                 stored in the referenced field.
#
# - cityField: used with field value for geocoder query
#
# TODO: Currently geoPicker fills fields of the `case` model. View for
# this model is hardcoded.
# 
# Arguments are picker field name and picker element.
this.geoPicker = (fieldName, el) ->
  addr = $(el).parents('.input-append')
              .children("input[name=#{fieldName}]")
              .val()

  view = elementView($(el))
  modelName = elementModel($(el))
  
  coord_field = modelField(modelName, fieldName).meta['targetCoords']
  map_field = modelField(modelName, fieldName).meta['targetMap']
  city_field = modelField(modelName, fieldName).meta['cityField']

  # TODO Drop hardcoded name of the «real» parent view (case-form)
  if city_field?
    addr = global.viewsWare['case-form'].knockVM[city_field]() + ", " + addr

  $.getJSON(nominatimQuery+"#{addr}", (res) ->
    if res.length > 0
      lonlat = new OpenLayers.LonLat(res[0].lon, res[0].lat)

      if coord_field?
        global.viewsWare['case-form'].knockVM[coord_field](lonlat.toShortString())

      if map_field?
        osmap = view.find("[name=#{map_field}]").data("osmap")
        osmap.setCenter(
              lonlat.transform(wsgProj, osmProj),
              zoomLevel)
        carBlip(osmap, osmap.getCenter()))


# Reverse geocoding picker (coordinates -> address)
#
# Recognized field metas:
# 
# - targetMap
#
# - targetAddr
this.reverseGeoPicker = (fieldName, el) ->
  coords =
    lonlatFromShortString(
      $(el).parents('.input-append')
           .children("input[name=#{fieldName}]")
           .val())
  view = elementView($(el))

  osmCoords = coords.clone().transform(wsgProj, osmProj)

  addr_field = modelField(modelName, fieldName).meta['targetAddr']
  map_field = modelField(modelName, fieldName).meta['targetMap']

  if map_field?
    osmap = view.find("[name=#{map_field}]").data("osmap")
    osmap.setCenter(osmCoords, zoomLevel)
    carBlip(osmap, osmap.getCenter())

  if addr_field?
    $.getJSON(nominatimRevQuery + "lon=#{coords.lon}&lat=#{coords.lat}",
      (res) ->
        addr = buildReverseAddress(res)

        global.viewsWare['case-form'].knockVM[addr_field](addr)
    )
