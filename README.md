BuildUpdate
===========

Summary
-------
Manages a bash script that update the current build environment based on TeamCity artifact dependencies.

Ubuntu 12.04 Install Requirements
--------------------
1. sudo apt-get install ruby1.9.1 ruby1.9.1-dev libxml2-dev libxslt-dev
2. sudo update-alternatives --config ruby (and select ruby 1.9.1)
2. sudo gem install bundler
3. git clone https://github.com/chrisvire/BuildUpdate
4. cd BuildUpdate
5. bundle install
6. sudo bundle exec gem pristine nokogiri

Windows Install Requirements
1. install Ruby (http://rubyinstaller.org/downloads/)
2. gem install bundler
3. git clone https://github.com/chrisvire/BuildUpdate
4. cd BuildUpdate
3. bundle install


How to use
----------
1. Create a buildupdate.sh script in your build directory with configuration.  
2. Run the buildupdate.rb script to update buildupdate.sh with all of the calls to update the current build environment.  
3. Then commit the buildupdate.sh script to source control.

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
