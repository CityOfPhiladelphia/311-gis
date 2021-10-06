var GIS = (function () {
  var $searchInput,
      $searchAction,
      $multipleResultsModal,
      $multipleResultsSelect,
      $multipleResultsButton,
      ANIMATION_DELAY = 250; // milliseconds

  return {
    config: GIS_CONFIG,
    // initial state. this is really only here to spec out what the state looks
    // like.
    // REVIEW should initial values be null, since they get reset to null on
    // each ais search?
    state: {
      // this is the ais feature that matched the user's search
      aisFeature: {},
      // this gets used when there are multiple matching ais features
      multipleResults: [],
      // this stores related data, such as service areas
      layerInfo: {},
    },
    init: function () {
      // configure proj4 to use local state plane projection
      proj4.defs('EPSG:2272', '+proj=lcc +lat_1=40.96666666666667 +lat_2=39.93333333333333 +lat_0=39.33333333333334 +lon_0=-77.75 +x_0=600000 +y_0=0 +ellps=GRS80 +datum=NAD83 +to_meter=0.3048006096012192 +no_defs ');

      $searchInput = $('#search-input');
      $searchAction = $('#search-action');

      // check for search input from parent page
      if (window.opener) {
        var searchInput = window.opener.getSearchInput();
        $searchInput.val(searchInput);

        // if there's search input, "click" the locate button
        if (searchInput.length > 0) {
          GIS.handleSearchButtonClick();
        }
      }

      // listen for 'enter' key on address input
      $searchInput.on('keyup', function (e) {
        if (e.keyCode == 13) {
          GIS.handleSearchButtonClick();
        }
      });

      // if there's something in the search input
      $('#search-button').click(GIS.handleSearchButtonClick);

      /*
      MULTIPLE RESULTS MODAL
      */

      $multipleResultsModal = $('#multiple-results-modal');
      $multipleResultsSelect = $multipleResultsModal.find('select');
      $multipleResultsButton = $multipleResultsModal.find('button');

      // callbacks
      $('.modal-close').click(function (e) {
        $multipleResultsModal.fadeOut(ANIMATION_DELAY);
      });
      $('.modal').click(function (e) {
        $multipleResultsModal.fadeOut(ANIMATION_DELAY);
      });
      $('.modal-content').click(function (e) {
        e.stopPropagation();
      });
      // $multipleResultsSelect.change(function (e) {
      $multipleResultsButton.click(function (e) {
        // get index of selected option
        var i = $multipleResultsSelect.find('option:selected').index();

        // pass selected address to ais callback
        // (this is not ideal but ais doesn't currently have a way to validate
        // a single address)
        var aisFeature = GIS.state.multipleResults[i],
            featureData = {
              features: [aisFeature],
            };
        GIS.didFetchAis(featureData);

        // empty dropdown
        $multipleResultsSelect.empty()
        // hide modal
        $multipleResultsModal.fadeOut(ANIMATION_DELAY);

        // clear out state
        GIS.state.multipleResults = null;
      });
    },

    setSearchAction: function (action) {
      // append ellipsis
      action && (action += '...');
      // set text
      $searchAction.text(action);
      // show search status if there's an action
      $('#search-status').toggle(!!action);
    },

    toCamelCase: function (s) {
      return s.replace(
        /\w+/g,
        function (w) {
          return w[0].toUpperCase() + w.slice(1).toLowerCase();
        }
      );
    },

    // handle clicks to the locate button
    handleSearchButtonClick: function (e) {
      GIS.setSearchAction('Validating address');

      var inputAddress = $searchInput.val();

      GIS.fetchAis(inputAddress);
    },

    // this function gets user input and queries the Address Information System. this is
    // intended to replace the Address Candidate function.
    fetchAis: function (inputAddress) {
      // console.log('fetch ais', inputAddress);

      var url = GIS.config.ais.baseUrl + encodeURIComponent(inputAddress);

      // clear out state
      GIS.state.aisFeature = null;
      GIS.state.layerInfo = null;

      $.ajax({
        url: url,
        data: GIS.config.ais.params,
        success: GIS.didFetchAis,
        error: GIS.didNotFetchAis,
      });
    },

    // on successful ais fetch
    didFetchAis: function (data) {
      // console.log('did fetch ais', data);

      GIS.setSearchAction(null);

      // check number of results
      var features = data.features,
        resultCount = Array.isArray(features) ? features.length : 0;

      if (resultCount === 1) {
        var feature = features[0];

        // WORKAROUND ais returns pipe-delimited address keys, so split them
        // and take the first one
        var addressKeysJoined = feature.properties.li_address_key || '',
            addressKeys = addressKeysJoined.split('|'),
            addressKey = addressKeys.length > 0 ? addressKeys[0] : null;
        feature.properties.li_address_key = addressKey;

        GIS.didGetValidAddress(feature);

      // if we got multiple results
      } else if (resultCount > 1) {
        GIS.state.multipleResults = features;

        // show dropdown
        GIS.showMultipleResults(features);

      // if we got no results
      } else {
        console.log('ais successful but no features');

        alert('Could not locate that address. Please try another search.');
      }
    },

    // on unsuccessful ais fetch
    didNotFetchAis: function (jqXHR, textStatus, errorThrown) {
      console.log('error fetching ais:', errorThrown, jqXHR);

      GIS.setSearchAction(null);

      var msg;

      if (errorThrown === 'NOT FOUND') {
        msg = 'Could not locate that address. Please try another search.'
      } else {
        msg = 'Error while validating address: ' + errorThrown;
      }

      alert(msg);
    },

    showMultipleResults: function (features) {
      $multipleResultsSelect.empty();

      _.forEach(features, function (feature) {
        var address = GIS.addressForFeature(feature),
            $option = $('<option>').text(address);
        $multipleResultsSelect.append($option);
      });

      $multipleResultsModal.fadeIn(ANIMATION_DELAY);
    },

    // returns the fully-standardized street address for an ais feature
    addressForFeature(feature) {
      var props = feature.properties,
          featureType = feature.ais_feature_type,
          address;

      // form address based on the feature type
      switch(featureType) {
        case 'address':
          address = props.street_address;
          break;

        case 'intersection':
          var comps = [
                props.street_1.street_full,
                props.street_2.street_full
              ],
              address = comps.join(' & ');
          break;

        default:
          throw new Error('Unhandled feature type: ' + featureType);
          break;
      }

      return address;
    },

    didGetValidAddress: function (feature) {
      // console.log('did get valid address', feature);

      var coords = feature.geometry.coordinates,
        x = coords[0],
        y = coords[1],
        address = GIS.addressForFeature(feature);

      // add marker and zoom
      GIS.map.addGeocodeMarker(x, y, address);
      GIS.map.zoomTo(x, y);

      // save to state
      GIS.state.aisFeature = feature;

      // if it's an address, get layer info
      if (feature.ais_feature_type === 'address') {
        var layerInfo = GIS.fetchLayerInfo(feature, null);
      // otherwise call the remaining two functions
      } else {
        // pass data back to parent
        GIS.saveGeodata();

        // get related/nearby cases
        GIS.fetchRelated();
      }
    },

    fetchLayerInfo: function (feature, caseType) {
      // console.log('fetch layer info', feature, caseType);

      GIS.setSearchAction('Querying layers');

      //var GIS_BASE_URL = '{!$Setup.GIS__c.ESRIServices__c}' + '/',
      var queryLayers = GIS.config.queryLayers,
          queryLayerFns = {};

      // build up an array of query fns for each layer
      _.forOwn(queryLayers, function (queryLayerDef, queryLayerName) {
        //console.log('query layer', queryLayerName, queryLayerDef);

        var queryLayerFn = function (callback) {
          //var endpoint = queryLayerDef.endpoint,
          var url = queryLayerDef.url,
            type = queryLayerDef.type,
            options = queryLayerDef.options;

          switch(type) {
            case 'esri':
              // form params
              var params = {
                  outFields: '*',
                  returnGeometry: 'true',
                  f: 'json'
                },
                whereFn = options.where,
                where = whereFn(feature);
              params.where = where;

              $.ajax({
                url: url + '/query',
                data: params,
                success: function (dataStr) {
                  // parse json string
                   console.log('testdatastringbefore', queryLayerName, data, url,dataStr);
                  try {
                  var data = $.parseJSON(dataStr);
                  } catch (e) {
                                // Let's assume the error is that we already have parsed the payload
                                // So just return that
                            var data = dataStr;
                  }
                     console.log('testdatasrtringafter', queryLayerName, data, url, dataStr);

                  // check for error
                  if (data.error) {
                    console.log('did get error for where query', queryLayerName, data);

                    callback(true);

                    return;
                  }

                  console.log('did get data for where query', queryLayerName, data, url);

                  // unpack attributes object
                  var features = data.features,
                    feature = Array.isArray(features) && features.length > 0 ? features[0] : null,
                    result;

                  if (feature)  {
                    result = feature.attributes;

                    console.log('set', queryLayerName, result);
                  }

                  callback(null, result);
                },
                error: function () {
                  console.log('did get esri error');

                  callback(queryLayerName + ' had error');
                }
              });

              break;

            case 'carto':
              var qFn = options.q,
                q = qFn(feature),
                params = {
                  q: q,
                };

              $.ajax({
                url: url,
                data: params,
                success: function (data) {
                  // unpack attributes
                  var rows = data.rows,
                    row = Array.isArray(rows) && rows.length > 0 ? rows[0] : null;

                  callback(null, row);
                },
                error: function () {
                  console.warn('did get carto error');

                  callback(queryLayerName + ' had error');
                },
              });

              break;

            default:
              console.warn('unhandled query type: ' + type);
              callback("unhandled query type '" + type + "'", null);

              break;
          }
        };

        queryLayerFns[queryLayerName] = queryLayerFn;
      });

      // execute query fns in parallel
      async.parallel(
        queryLayerFns,
        // then do this
        function (err, results) {
          // check for an error
          if (err) {
            alert('An error occurred while querying layers. Please try again.');
            console.log('async parallel error:', err);
            return;
          }

          // console.log('async parallel finished', results);

          // save to state
          GIS.state.layerInfo = results;

          // pass data back to parent
          GIS.saveGeodata();

          // get related/nearby cases
          GIS.fetchRelated();
        }
      );
    },

    // this takes an optional argument `parentCase` which is used when relating
    // cases. parentCase should be an object with two keys: id and caseNumber.
    // id is the guid of the case, and caseNumber is the shorter numeric id.
    saveGeodata: function (parentCase) {
      console.log('save geodata', feature, layerInfo);

      var state = GIS.state,
          feature = state.aisFeature,
          layerInfo = state.layerInfo;
          // parentId = state.parentId;

      // pass data back to parent window
      var geodata = GIS.createGeodataObject(feature, layerInfo, parentCase);
      console.log('geodata', geodata);

      // DEBUG: if window.opener isn't defined, we're probably just testing this
      // from the X311GISMap page directly. don't try to call saveGeodata on the parent.
      if (!window.opener) {
        console.warn('window.opener not defined. geodata will not be saved.');
        return;
      }

      window.opener.saveGeodata(geodata);
    },

    // takes an ais feature and formats it as a "geodata" object which the parent window can understand.
    createGeodataObject: function (feature, layerInfo, parentCase) {
      console.log('create geodata object', feature, layerInfo);

      var props = feature.properties,
          coords = feature.geometry.coordinates,
          coordsStatePlane = proj4('EPSG:2272', coords),
          // parent page checks for the token `Intersection`, so camel case this
          matchType = GIS.toCamelCase(feature.ais_feature_type),
          addressKey = (props.li_address_key || '').split('|')[0],
          pwdParcel = props.pwd_parcel_id,
          parentCase = parentCase || {},
          parentId = parentCase.id,
          label = parentCase.num;

      // we're now getting the L&I district from AIS
      if (layerInfo) {
        layerInfo.district = props.li_district;
      }

      var geodata = {
          gisData: {
            standardizedAddress: GIS.addressForFeature(feature),
            matchType: matchType,
            // address keys are pipe-delimited, so take the first one
            addressKey: addressKey,
            pwdParcel: pwdParcel,
            // REVIEW is it ok to use the opa address here?
            liAddress: props.opa_address,
            zoning: props.zoning,
          },

          // this doesn't seem to be used
          description: null,

          // this doesn't seem to be used
          featureData: null,

          // this gets passed in when "relating" one case to another
          parentId: parentId,

          // this is the number that populates the parent case field when
          // relating
          label: label,

          x: coords[0],
          y: coords[1],
          x2272: coordsStatePlane[0],
          y2272: coordsStatePlane[1],

          layerInfo: layerInfo,

          // this seems to be where service area values go
          attributes: {
            // this is not a service area in ais, so fake it like this.
            SA_STREETS_ZipCode: props.zip_code,
          }
        };

      // map service areas
      var serviceAreas = GIS.config.serviceAreas;

      _.forOwn(serviceAreas, function (aisKey, ulrsKey) {
        var val = props[aisKey];
        geodata.attributes[ulrsKey] = val;
      });

      return geodata;
    },

    fetchRelated: function () {
      // console.log('fetch related');

      GIS.setSearchAction('Locating nearby cases');

      var feature = GIS.state.aisFeature,
          coords = feature.geometry.coordinates,
          x = coords[0],
          y = coords[1],
          RADIUS = GIS.config.nearbyRadius;

      // get "related" cases (recent, nearby cases with the same record type)
      var recordTypeId = window.opener && window.opener.RECORD_TYPE_ID;

      // DEBUG: if no parent window, use record type id for Dangerous Sidewalk
      if (!recordTypeId) recordTypeId = '012G00000014Gt6IAE';

      // get cases with the same record type within a radius
      GisClient.QueryByRadius(recordTypeId, x, y, RADIUS, GIS.didFetchRelated);
    },

    didFetchRelated: function (results, event) {
      // console.log('did fetch related', results, event);

      GIS.setSearchAction(null);

      // put markers on map
      GIS.map.addRelatedMarkers(results);
    },
  };
})();

$(GIS.init);
