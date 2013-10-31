BuildUpdate
===========

Summary
-------
Manages a bash script that update the current build environment based on TeamCity artifact dependencies.

How to use
----------
Create a buildupdate.sh script in your build directory with configuration.  Run the buildupdate.rb script to update buildupdate.sh with all of the calls to update the current build environment.  Then commit the buildupdate.sh script to source control.

File format
-----------

The configuration is in comments at the beginning of the file.  Use the variables: 
* server: specifies the the hostname of the TeamCity Server
* project: the name of the TeamCity project
* build: the name of the TeamCity build configuration
* build_type: the internal TeamCity buildType id

You can use project/build or build_type.  The script will resolve project/build to build_type by querying TeamCity.

Variable can be specified by OS (windows, linux, osx, unix).  The most specific will be used.

```bash
#!/bin/bash
# server=build.palaso.org
# project=WeSay Windows
# build.windows=WeSay-win32-1.4-continuous
# build.linux=WeSay-precise64-DefaultMono Continuous
```
