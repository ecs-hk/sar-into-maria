CREATE USER 'writer'@'%' IDENTIFIED BY 'xx';
CREATE USER 'reader'@'%' IDENTIFIED BY 'xx';

GRANT SELECT, INSERT, UPDATE, DELETE ON Sardata.* TO 'writer'@'%';
GRANT SELECT ON Sardata.* TO 'reader'@'%';

FLUSH PRIVILEGES;
