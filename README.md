## *hashview* ##

**hashview** is a web application designed by penetration testers to help organize and automate the repetitious tasks related to password cracking and analysis.

** THE VERSION 1.00 IS CURRENTLY STILL IN BETA **

### License ###

**hashview** is licensed under the XXXXX license. Refer to XXXXX for more information.

### Installation ###

1) Ensure you have a working version of oclHashcat or hashcat before using Hashview
2) Install Ruby 2.1.5 ( We suggest RVM for this)
3) Install sqlite3, redis-server, bundler, rake, libmysqlclient-dev ( package names fit for ubuntu 14.04, anything else and good luck)
4) Ensure redis service is running and listening on the proper port
5) Run bundle install from root dir of the git repo
6) run "ruby main.rb" in the root dir of the git repo

### Usage/Help ###

Contact devs via Github page

### Contributing ###

Contributions are welcome and encouraged, provided your code is of sufficient quality. Before submitting a pull request, please ensure your code adheres to the following requirements:

1. Licensed under XXXX
2. Blah blah something about tab vs spaces size blah

You can use GNU Indent to help assist you with the style requirements:

```
indent -st -bad -bap -sc -bl -bli0 -ncdw -nce -cli0 -cbi0 -pcs -cs -npsl -bs -nbc -bls -blf -lp -i2 -ts2 -nut -l1024 -nbbo -fca -lc1024 -fc1
```

Your pull request should fully describe the functionality you are adding/removing or the problem you are solving. Regardless of whether your patch modifies one line or one thousand lines, you must describe what has prompted and/or motivated the change.

Solve only one problem in each pull request. If you're fixing a bug and adding a new feature, you need to make two separate pull requests. If you're fixing three bugs, you need to make three separate pull requests. If you're adding four new features, you need to make four separate pull requests. So on, and so forth.

If your patch fixes a bug, please be sure there is an [issue](https://github.com/hashview/hashview) open for the bug before submitting a pull request.

The project lead has the ultimate authority in deciding whether to accept or reject a pull request. Do not be discouraged if your pull request is rejected!

### Thanks!
