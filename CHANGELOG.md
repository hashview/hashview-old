# Change Log
Notable changes will be documented here

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
