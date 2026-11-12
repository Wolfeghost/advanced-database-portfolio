@echo off
REM =====================================================================
REM LagosCare Clinics — Portfolio 4: Load the MySQL exports into MongoDB
REM Requires MongoDB Database Tools (mongoimport) on the PATH.
REM Run from the portfolio-4-nosql folder AFTER 02_create_collections.js.
REM
REM Local server:  just run  03_import.cmd
REM MongoDB Atlas: first set your connection string (include the database
REM                name "lagoscare" before the "?"), e.g.
REM   set MONGO_URI=mongodb+srv://wale:YOUR_PASSWORD@lagoscare.abcde.mongodb.net/lagoscare
REM   03_import.cmd
REM
REM mongoimport reads one JSON document per line and understands Extended
REM JSON ({"$date": ...}, {"$numberDecimal": ...}). Every document is checked
REM by the collection's $jsonSchema validator as it is inserted; any
REM rejected document is reported as an error and counted as "failed".
REM =====================================================================

if "%MONGO_URI%"=="" set MONGO_URI=mongodb://localhost:27017/lagoscare

mongoimport --uri "%MONGO_URI%" --collection patients       --file data\patients.json
mongoimport --uri "%MONGO_URI%" --collection encounters     --file data\encounters.json
mongoimport --uri "%MONGO_URI%" --collection pharmacy_stock --file data\pharmacy_stock.json

echo.
echo Expected: 20008 patients, 95744 encounters, 14 stock documents, 0 failed.
