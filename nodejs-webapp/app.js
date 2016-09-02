// -------------------------------------------------------------------------
// Variable definitions
// -------------------------------------------------------------------------
var express = require('express'),
    morgan = require('morgan'),
    bodyParser = require('body-parser'),
    routes = require('./routes'),
    http = require('http'),
    path = require('path'),
    fs = require('fs'),
    helmet = require('helmet');

var app = express();

var server = http.createServer(app);

// -------------------------------------------------------------------------
// MariaDB connection info sucked in from config file
// -------------------------------------------------------------------------
var mariaConnInfo = fs.readFileSync(path.join(__dirname, 'site-config',
        'db-connection.json')),
    mariaConnInfo = JSON.parse(mariaConnInfo);

// -------------------------------------------------------------------------
// Listen IP address and port sucked in from config file
// -------------------------------------------------------------------------
var httpListener = fs.readFileSync(path.join(__dirname, 'site-config',
        'http-server.json')),
    httpListener = JSON.parse(httpListener);

// -------------------------------------------------------------------------
// Express setup
// -------------------------------------------------------------------------
app.use(helmet());

app.set('views', path.join(__dirname, 'views'));
app.set('view engine', 'ejs');
app.use(express.static(path.join(__dirname, 'bower_components')));

app.locals.mariaConnInfo = mariaConnInfo;

app.use(morgan('combined'));

app.use(bodyParser.urlencoded({extended: false}));
app.use(bodyParser.json());

// -------------------------------------------------------------------------
// Express routes
// -------------------------------------------------------------------------
app.get('/', routes.index);
app.get('/graphs', routes.getGraphs);

// -------------------------------------------------------------------------
// Express error handling
// -------------------------------------------------------------------------
// Handle HTTP 404 if we didn't match any of the routes above
app.use(function(req, res) {
  res.status(404);
  res.render('error.ejs', {title: 'HTTP 404: not found'});
});

// Handle HTTP 500 if we hit an application error
app.use(function(err, req, res, next) {
  res.status(500);
  res.render('error.ejs', {title: 'HTTP 500: internal error',
      error: err});
});

// -------------------------------------------------------------------------
// Start the Express HTTP server
// -------------------------------------------------------------------------
server.listen(httpListener.port, httpListener.ip, function(){
    console.log('HTTP server listening on ' + JSON.stringify(httpListener));
});
