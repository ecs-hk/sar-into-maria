# sar-into-maria

## Synopsis

sar(1) data collector cronjob and a frontend web (graphing) app. Data collector is a bash script that uses jq(1) and several common CLI utilities. Web app is built with Node.js, Chartist.js, and other excellent tools from the Javascript ecosystem.

* Data collector script tested on EL 6, EL 7, and Debian 8.
* Web app tested on EL 7 using Node.js v4.5.* LTS.

## Screenshots

![Screenshot](/README.md-img/graphs.png?raw=true)

![Screenshot](/README.md-img/graphs-w-details.png?raw=true)

---

## Create the MariaDB tables and accounts

Run the SQL in this project's `sql` directory. (Update the SQL to use strong service account passwords before running it.)

```
cd sar-into-maria/sql
mysql -u root -h db01.org.local -p < sql/setup-db.sql 
mysql -u root -h db01.org.local -p < sql/setup-service-accounts.sql 
```

---

## Deploy the data collector on all systems

* Copy the script, DB credentials, and cronjob:
```
cd sar-into-maria/collector-script
sudo cp sar-into-maria.bash /usr/local/sbin
sudo cp sar-into-maria.json /usr/local/etc
sudo cp sar-collector-cronjob /etc/cron.d
```

* Set permissions correctly:
```
sudo chmod 0700 /usr/local/sbin/sar-into-maria.bash
sudo chmod 0600 /usr/local/etc/sar-into-maria.json
sudo chmod 0644 /etc/cron.d/sar-collector-cronjob
```

* Edit `sar-into-maria.json` to reflect your MariaDB setup.

---

## Deploy the web app on a single system

* Download and install [Node.js](https://nodejs.org) LTS
* Set up your environment, e.g.:
```
_d=/path/to/node-v4.x.y
export NODE_PATH=${_d}/lib/node_modules
export PATH=/usr/bin:/bin:${_d}/bin
```
* Install Node.js and frontend dependences:
```
cd sar-into-maria/nodejs-webapp
npm install
./node_modules/bower/bin/bower install
```
* Set up HTTP server and MariaDB connection (after copying the two files, edit both to match your desired settings):
```
cd sar-into-maria/nodejs-webapp/site-config
cp http-server.json.EXAMPLE http-server.json
cp db-connection.json.EXAMPLE db-connection.json
```

## Run the web app

* Set up your environment (if you haven't already), a la:
```
_d=/path/to/node-v4.x.y
export NODE_PATH=${_d}/lib/node_modules
export PATH=/usr/bin:/bin:${_d}/bin
```
* Launch it
```
cd sar-into-maria/nodejs-webapp
node app.js
```
