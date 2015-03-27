BuildUpdate
===========

Summary
-------
Manages a bash script that update the current build environment based on TeamCity artifact dependencies.  Ruby 1.9.x is required.  It is known to have issues with with Ruby 2.x and will not work.

Ubuntu 12.04 Install Requirements
--------------------
1. `sudo apt-get install ruby1.9.1 ruby1.9.1-dev libxml2-dev libxslt-dev`
2. `sudo update-alternatives --config ruby` (and select ruby 1.9.1)
2. `sudo gem install bundler`
3. `git clone https://github.com/chrisvire/BuildUpdate`
4. `cd BuildUpdate`
5. `bundle install`
6. `sudo bundle exec gem pristine nokogiri` (this removes a warning about library incompatibility)

Windows Install Requirements
----------------------------
1. You need a way to run shell scripts, e.g. [Cygwin](http://www.cygwin.com/) or [msysgit](http://msysgit.github.io/) (which includes Git Bash)
2. install Ruby (http://rubyinstaller.org/downloads/ -- use 1.9.x)
3. `gem install bundler`
4. `git clone https://github.com/chrisvire/BuildUpdate`
5. `cd BuildUpdate`
6. `bundle install`


Create the shell script
----------
1. Create a buildupdate.sh script in your build directory with configuration (see below).  
2. Run the buildupdate.rb script to update buildupdate.sh with all of the calls to update the current build environment.
3. Commit the buildupdate.sh script to source control.

When you change the dependencies
----------
1. Run `buildupdate.rb`, as in

`c:\dev\bloom> c:\dev\bin\BuildUpdate\buildupdate.rb -f buildupdate.sh`

The updated version of buildupdate.sh will be part of your commit.

When you change branches
----------
1. Run `buildupdate.sh` to get the correct dependencies for that branch.

File format
-----------

The configuration is in comments at the beginning of the file.  Use the variables: 
* server: specifies the the hostname of the TeamCity Server
* project: the name of the TeamCity project
* build: the name of the TeamCity build configuration
* build_type: the internal TeamCity buildType id

You can either specify `project` & `build`, or specify `build_type`.  It is better to use `build_type` since it will not change if someone changes the displayed `project` or `build` names (which some people will do without notice and break regenerating the script).  To determine the `build_type`, browse to the build in the TeamCity Web Interface.  For example, browse to http://build.palaso.org and select "libpalaso" project and "palaso-precise64-master Continuous" build and the url will be http://build.palaso.org/viewType.html?buildTypeId=bt322 so the `build_type` is `bt322`.

```bash
#!/bin/bash
# server=build.palaso.org
# build_type=bt322
```

You can declare different values for these parameters for each OS (windows, linux, osx, unix).  The most specific will be used. For example:

```bash
#!/bin/bash
# server=build.palaso.org
# project=WeSay Windows
# build.windows=WeSay-win32-1.4-continuous
# build.linux=WeSay-precise64-DefaultMono Continuous
```

Developers
----------
Please reports issues through [repo issues](https://github.com/chrisvire/BuildUpdate/issues/).
If you like to contribute, please fork the repo and send pull requests.
I will document debugging tips on the [repo wiki](https://github.com/chrisvire/BuildUpdate/wiki).
