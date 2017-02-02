var assert = require('assert'),
    maria = require('mariasql'),
    moment = require('moment'),
    debug = false;

function validHostname(suspect) {
  // Valid URI hostnames can only contain letters, numbers, and hyphens,
  // and they cannot begin or end with a hyphen.
  var re = /^[a-z0-9]+([a-z0-9]|\.|\-)*[a-z0-9]+$/i;
  if(!suspect) {
    return false;
  }
  if(re.test(suspect)) {
    return true;
  }
  return false;
}

function validSelectedHours(h) {
  // Valid selections are:
  // 1 hour, 4 hours, 1 day, 7 days
  if(h === '1' || h === '4' || h === '24' || h === '168') {
    return true;
  }
  return false;
}

function respondWithServerError(errMsg, res) {
  res.status(500);
  res.render('error.ejs', {title: 'HTTP 500: internal error', error: errMsg});
}

function respondWithClientError(errMsg, res) {
  res.status(400);
  res.render('error.ejs', {title: 'HTTP 400: bad request', error: errMsg});
}

function queryHostsAndRespond(req, res, sqlQuery) {
  var connInfo = req.app.locals.mariaConnInfo,
      c = new maria(connInfo),
      ejsObj = {};

  c.query(sqlQuery, function(err, rows) {
    if(err) {
      console.log(err);
      respondWithServerError('MariaDB error', res);
      return;
    }

    if(rows.length === 0) {
      respondWithClientError('No results', res);
      return;
    }

    var lastRow = rows.length - 1;

    ejsObj['results'] = rows;
    ejsObj['title'] = 'sar data';

    res.render('index.ejs', ejsObj);
    c.end();
  });
}

function querySarDataAndRespond(req, res, sqlQuery, hours) {
  var connInfo = req.app.locals.mariaConnInfo,
      c = new maria(connInfo),
      ejsObj = {'timeWindow': hours};

  c.query(sqlQuery, function(err, rows) {
    if(err) {
      console.log(err);
      respondWithServerError('MariaDB error', res);
      return;
    }

    if(rows.length === 0) {
      respondWithClientError('No results', res);
      return;
    }

    var lastRow = rows.length - 1;

    ejsObj['results'] = rows;
    ejsObj['prettyStartTime'] = moment(rows[0].LoggedTime).format('MMM D') +
        ', ' + moment(rows[0].LoggedTime).format('HH:mm');
    ejsObj['prettyEndTime'] = moment(rows[lastRow].LoggedTime).format('MMM D') +
        ', ' + moment(rows[lastRow].LoggedTime).format('HH:mm');
    ejsObj['hostname'] = rows[0].Hostname;
    ejsObj['title'] = rows[0].Hostname + ' graphs';

    res.render('graphs.ejs', ejsObj);
    c.end();
  });
}

exports.index = function(req, res) {
  var q = 'SELECT DISTINCT Hostname FROM QuickPerf';
  queryHostsAndRespond(req, res, q);
};

exports.getGraphs = function(req, res) {
  var host = req.query.hostSelection,
      hours = req.query.hoursSelection;

  if(!validSelectedHours(hours)) {
    respondWithClientError('Invalid hours search criteria', res);
    return;
  } else if(!validHostname(host)) {
    respondWithClientError('Invalid hostname search criteria', res);
    return;
  } else {
    var past = moment().subtract(hours, 'hours').format('YYYY-MM-DD HH:mm:ss'),
        q = 'SELECT * FROM QuickPerf ' +
            'WHERE Hostname = "' + host + '" ' +
            'AND LoggedTime > "' + past + '" ' +
            'ORDER BY LoggedTime ASC';
    querySarDataAndRespond(req, res, q, hours);
  }
}
