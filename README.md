# sar-into-maria

## Synopsis

sar(1) data collector cronjob and a frontend web (graphing) app. Data collector is a bash script that uses jq(1) and several common CLI utilities. Web app is built with Node.js, Chartist.js, and other excellent tools from the Javascript ecosystem.

* Data collector script tested on EL 6, EL 7, and Debian 8.
* Web app tested on EL 7 using Node.js v4.5.* LTS.

## Screenshots

![Screenshot](/README.md-img/index.png?raw=true)

![Screenshot](/README.md-img/graphs-w-details.png?raw=true)

---

## Create the MariaDB tables and accounts

* Copy the SQL files:
```shell
cd sar-into-maria/sql
cp setup-db.sql ~
cp setup-service-accounts.sql ~
```

* Edit `~/setup-service-accounts.sql` to use strong passwords.

* Run the edited SQL:
```shell
cd sar-into-maria/sql
mysql -u root -h db01.org.local -p < ~/setup-db.sql 
mysql -u root -h db01.org.local -p < ~/setup-service-accounts.sql 
```

---

## Deploy the data collector on all systems

* Copy the script, DB credentials, and cronjob:
```shell
cd sar-into-maria/collector-script
sudo cp sar-into-maria.bash /usr/local/sbin
sudo cp sar-into-maria.json /usr/local/etc
sudo cp sar-collector-cronjob /etc/cron.d
```

* Set permissions correctly:
```shell
sudo chmod 0700 /usr/local/sbin/sar-into-maria.bash
sudo chmod 0600 /usr/local/etc/sar-into-maria.json
sudo chmod 0644 /etc/cron.d/sar-collector-cronjob
```

* Edit `/usr/local/etc/sar-into-maria.json` to use your MariaDB connection and an account with SELECT,INSERT,UPDATE,DELETE privileges.

---

## Deploy the web app on a single system

* Download and install [Node.js](https://nodejs.org) LTS

* Set up your environment:
```shell
_d=/path/to/node-v4.5.*
export NODE_PATH=${_d}/lib/node_modules
export PATH=/usr/bin:/bin:${_d}/bin
```

* Install web app dependences:
```shell
cd sar-into-maria/nodejs-webapp
npm install
./node_modules/bower/bin/bower install
```

* Set up HTTP server and MariaDB connection:
```shell
cd sar-into-maria/nodejs-webapp/site-config
cp db-connection.json.EXAMPLE db-connection.json
cp http-server.json.EXAMPLE http-server.json
```

* Edit `db-connection.json` to use your MariaDB connection and an account with SELECT privileges.

* Edit `http-server.json` with IP and port settings appropriate for your environment.

---

## Run the web app

* Set up your environment (if you haven't already):
```shell
_d=/path/to/node-v4.5.*
export NODE_PATH=${_d}/lib/node_modules
export PATH=/usr/bin:/bin:${_d}/bin
```

* Launch it
```shell
cd sar-into-maria/nodejs-webapp
node app.js
```
