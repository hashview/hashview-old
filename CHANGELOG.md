# Change Log
Notable changes will be documented here

## Current Release
## [v0.7.4-beta] - 2018-xx-xx
### Added
- Added new Analytics portlet "charset breakdown"
- Extended Masks list to be to 10 instead of top 4.
- Added Hashfile to Job listings
- Added ability to create new tasks mid job creation. New tasks are automatically applied to the job.
- Added new wordlist type (dynamic). These wordlists are dynamic as in they are ever changing based on outside conditions.
- Newly imported hashfiles automatically trigger and generate a corresponding dynamic wordlist. 
- Added more info for Tasks and Wordlists, now you can easily see which tasks are assigned to what job, and what wordlists are assigned to what tasks.
- Added dynamic chunking! Now each agent will work on chunks based off of their computed benchmarks.
- Added fail check when hashfile fails import and loads a hashfile of 0/0.

### Changed
- The Last Updated value for jobs has been changed to Job Owner. This value is no longer updated when a user edits a job.

### Removed

### Fixed
- Fixed issue when reordering tasks.
- Fixed bug where getBusy? function was incorrectly citing if hashview was busy.
- Now prevents the creation of a job with no tasks assigned.
- Fixed time run calculation bug used in hashfiles
- Fixed bug where keyspace was improperly being calculated for new task when hashcat was actively running.
- Fixed bug where rule name was not properly displaying in jobs listing
- Fixed bug where hashfiles were failing to delete as they were falsely reporting as being associated to a job.

## [v0.7.3-beta] - 2018-01-10
### Added
- Added support for $user:$hash:$salt hashtypes (thanks https://github.com/GrepItAll): https://github.com/hashview/hashview/issues/373
- Added support for sequel (vs data mapper) (MAJOR THANKS to https://github.com/nicbrink)
- Added support for hashtype 2811 (IPB 2+)
- Added support for optimized drivers (-O)

### Removed

### Fixed
- Fixed issue with chunking calculations: https://github.com/hashview/hashview/issues/358
- Fixed calculation of password complexity in analytics page: https://github.com/hashview/hashview/issues/360 
- Fixed hard crash error when attempting to delete non-existent file: https://github.com/hashview/hashview/issues/365
- Updated Gemlock to require rubocop 0.51.0 due to security vulns.
- Fixed issue where Time Remaining listed in the jumbo tron was not properly populating (note requires agent update if using distributed): https://github.com/hashview/hashview/issues/371
- Fixed task list when adding tasks to new jobs. Now no longer lets you select a task that was already assigned.

## [v0.7.2-beta] - 2017-10-19
### Added
 - Added Logging Facility, logs should now be under /hashview/logs/\*.log and /hashview/logs/jobs/\*.log (Logs will rotate daily. Logs greater than 30 days will be automatically deleted
 - Added collapsing window in analytics in Weak Account Password
 - Added ability to download user accounts/passwords for accounts that are found to be weak in csv format
 - Added ability to set OTP passwords for users using google authenticate (thanks: https://github.com/nicbrink)
 
### Removed
 - Wordlist Checksums is no longer a background task that fires every 5 seconds. Instead its queued up by wordlist importer.

### Fixed
 - Fixed calculation bug where SmartWordlist was being refactored into new SmartWordlist. Now calculations are quicker
 - Fixed (hopefully) bug where hashview prematurely 'completes' a job (and subsequently kills a running task). This only happens in rare cases where multiple agents are involved. 
 - Fixed (hopefully) issue where threads not exiting when they're told to. This resulted in issues related to: https://github.com/hashview/hashview/issues/264
 - Fixed issue where rules listed under task details was displaying rule.id, and not the rule.name: https://github.com/hashview/hashview/issues/342
 - Fixed SMTP sender error experienced when user sends test message
 https://github.com/hashview/hashview/issues/341
 - Fixed issue where foreign DB's listed in config were not being connected too: https://github.com/hashview/hashview/issues/351

## [v0.7.1-beta] - 2017-09-04
### Added
 - Rake task to reset db (thanks: nicbrink)
 - New hub route/tab if registered
 - Additional step in job creation (if hub enabled) asking permission to check for cracked hashes before continuing
 - Added ability to reorder & delete tasks of a job mid creation and edit. 

### Removed
 - Hub check upon loading hashfiles list (no one was using it)
 - Hub upload function upon searches, job creation (no one was using it)

### Fixed
 - Fixed issue where importing the same hash twice into the db where one had an incorrect hashtype resulted in a 500 error. Now the entry is updated with the new hashtype.
 - Fixed timeouts when searching large hash sets with Hashview Hub

## [v0.7.0-beta] - 2017-07-22
### Added
 - Support for distributed cracking through hashview-agents
 - New type of wordlist 'Smart Wordlist'
 - Beta Hashview Hub (tm) integration
 - New management console for agents and Rules (you can now edit your rules within the app)
 - 3 new analytic portlets
 - Support for 50 more hashes

### Fixed
 - Calculation error on Analytics where on the global page for number of cracked hashes vs uncracked hashes.
 
## [v0.6.1-beta] - 2017-04-25
### Added
 - Support for 38 more hashes
### Fixed
 - Raced condition when importing wordlists (both via gui and cli)
 - Bug where NetNTLMv1 and NetNTLMv2 hashes were not properly importing
 - Bug where usernames were not being parsed when importing NetNTLMv1 and NetNTLMv2 hashes

## [v0.6.0-beta] - 2017-03-28
### Added
 - Resque 'management' queue for system jobs
 - Background job for automatically importing wordlists scp'd to control/wordlists
 - Background job for removing old temp files.
 - Support for user to set a SMTP Sender Name
 - Themes!! (we personally like slate)
 - Support for new hashcat settings: --force, --opencl-device-types, --workload-profile, --gpu-temp-disable, --gpu-temp-abort, --gpu-temp-retain
 - Ability to copy/paste hashfiles into new jobs as their being created
 - Support for smart hashdump and username:[NTLM hash] hashfiles
 - Two new rule sets for high and low utility
 - Support for cracking and importing hashes with salts
 - Support for more hashes: [import only] md5($pass.$salt), md5($salt.$pass), md5(unicode($pass).$salt), md5($salt.unicode($pass)), 	HMAC-MD5 (key = $pass), HMAC-MD5 (key = $salt), sha1($pass.$salt), sha1($salt.$pass), sha1(unicode($pass).$salt), sha1($salt.unicode($pass)), HMAC-SHA1 (key = $pass), HMAC-SHA1 (key = $salt), Domain Cached Credentials (DCC), MS Cache, 	sha256($pass.$salt), sha256($salt.$pass), sha256(unicode($pass).$salt), sha256($salt.unicode($pass)), HMAC-SHA256 (key = $pass), HMAC-SHA256 (key = $salt), vBulletin < v3.8.5 and vBulletin >= v3.8.5
 
### Changed
 - Moved queue management for cracking tasks from redis/resqueu to mysqld
 - Expanded hashes table to allow for hashes up to 1024 characters in length
 - Rake task db:upgrade will now automatically detect previous versions (starting with v0.5.1) and automatically upgrade your db and import current settings, users, cracked hashes, wordlists to new versions as they come out
 - Startup proccess from two cmds to single foreman cmd
 - Cracked output is now in hex format (better for importing symbols and other characters)
 - Default sender address of emails from no-reply@Pony to no-reply@hashview
 - Global settings is split into multiple panels for easier use.
 
### Fixed
 - Bug in combinator crack command
 - Searches now include wildcards before/after submitted string
 - Searches now remember what search type you entered
 - Jumbo tron now properly updates status on page refresh
 - Issue where Queued jobs are not being displayed on home page should be fixed
 - You should now be prevented from editing a job that is running or queued
 - Prevent the assignment of the same task twice to a job

## [v0.5.1-beta] - 2016-02-19
### Changed
- changed from Sinatra classic style to modular style

## [v0.5-beta] - 2016-02-04
### Changed
- changed db schema to accomadate very large datasets
- improved performance via db queries

## [v0.4-beta] - 2016-10-18
### Changed
- Encompasses all changes since the v0.3 tagged release

## [v0.3-beta] - 2016-10-18
### Changed
- Moved retrochecks from hashfile import to job start

### Fixed
- Fixed unauth message on invalid login attempts

## 2016-10-11
### Added
- Added download of uncracked hashes in download section

### Fixed
- Fixed bug where download file name of cracked passwords was not properly rendering

## 2016-10-10
### Fixed
- Fixed bug where stopping jobs and tasks failed to handle properly

### Changed
- Updated Job descriptions

## 2016-10-09
### Changed
- Changed support format for DSUser from v1.2 to v1.3

## 2016-10-07
### Changed
- Code Cleanup

## 2016-10-06
### Added
- Added support for Combinator attacks

## 2016-10-03
### Added
- Added Support for NTDSXtract (dsusers)
- Added 'importing' status for jobs and tasks

## 2016-10-02
### Removed
- Removed ability for basewords in analytics to be null

### Changed
- Rounded Run time calculated in analytics
- Prevented the deletion of a task if un an active job

## 2016-09-29
### Changed
- Code Cleanup

## 2016-09-28
### Added
- Expanded test cases
- Removed old 

## 2016-09-26
### Changed
- Fixed NetNTLMv1 and NetNTLMv2 parse bug
- Updated Jobsq to support NetNTLMv1 and NetNTLMv2

## 2016-09-23
### Removed
- Removed implicit downcase for non-LM hash imports


[v0.5.1-beta]: https://github.com/hashview/hashview/compare/v0.5-beta...v0.5.1-beta
[v0.5-beta]: https://github.com/hashview/hashview/compare/v0.4-beta...v0.5-beta
[v0.4-beta]: https://github.com/hashview/hashview/compare/v0.3-beta...v0.4-beta
[v0.3-beta]: https://github.com/hashview/hashview/compare/v0.1-alpha...v0.3-beta
