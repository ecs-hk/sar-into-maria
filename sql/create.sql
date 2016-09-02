CREATE DATABASE Sardata;

USE Sardata;

/* QuickPerf is designed such that each row represents a host + timestamp
   piece of sar data. Additional tables (CPU, Disk) hash out details for
   per-CPU and per-disk device data. */
CREATE TABLE QuickPerf
(
        Hostname varchar(80) NOT NULL,
        LoggedTime datetime NOT NULL,
        RAMUsedPct float NULL,
        SwapUsedPct float NULL,
        CPUIdlePct float NULL,
        CPUIOWaitPct float NULL,
	PRIMARY KEY (Hostname,LoggedTime)
);

CREATE TABLE CPU
(
        Hostname varchar(80) NOT NULL,
        LoggedTime datetime NOT NULL,
        CPUNumber int(5) NOT NULL,
        CPUIdlePct float NULL,
        CPUIOWaitPct float NULL,
	PRIMARY KEY (Hostname,LoggedTime,CPUNumber)
);

CREATE TABLE Disk
(
        Hostname varchar(80) NOT NULL,
        LoggedTime datetime NOT NULL,
        Devname varchar(50) NOT NULL,
        IOUtilPct float NULL,
        IOWaitMsecsAvg float NULL,
        QueueLengthAvg float NULL,
	PRIMARY KEY (Hostname,LoggedTime,Devname)
);
