BuildUpdate
===========

Summary
-------
This Ruby scripts manages a bash script that update the build environment on a developer's machine
to match the environment used on TeamCity.  The generated bash script will download
the artifact dependencies needed for the project.

Windows Install Requirements
----------------------------
* Install bash via [msysgit](http://msysgit.github.io/) (which includes Git Bash) or [Cygwin](http://www.cygwin.com/)
* Install the latest [Ruby](http://rubyinstaller.org/downloads/) -- Tested 1.9.3 & 2.3.1
  * Check "Add Ruby executables to your PATH"
  * Check "Associate .rb and .rbw files with this Ruby installation"
* `gem install bundler`
  * With Ruby 2.3.1, you will get this error `Unable to download data from https://rubygems.org/ - SSL_connect returned=1...` 
  * do the following [workaround](https://gist.github.com/eyecatchup/20a494dff3094059d71d) from a cmd window (not git bash)
  
```
# 1. Add insecure source
> gem sources -a http://rubygems.org/
https://rubygems.org is recommended for security over http://rubygems.org/

Do you want to add this insecure source? [yn]  y
http://rubygems.org/ added to sources

# 2. Remove secure source
> gem sources -r https://rubygems.org/
https://rubygems.org/ removed from sources

# 3. Update source cache
> gem sources -u
source cache successfully updated
```

* `git clone https://github.com/chrisvire/BuildUpdate`
* `cd BuildUpdate`
* `bundle install`

Ubuntu 16.04 & 14.04 Install Requirements
--------------------
The default version of Ruby for Ubuntu 16.04 is 2.3.1.
The default version of Ruby for Ubuntu 14.04 is 1.9.3.

1. `sudo apt-get install ruby ruby-dev zlib1g-dev`
2. `sudo gem install bundler`
3. `git clone https://github.com/chrisvire/BuildUpdate`
4. `cd BuildUpdate`
5. `bundle install`

Ubuntu 12.04 Install Requirements
--------------------
The default version of Ruby in Ubuntu 12.04 is Ruby 1.8.  This script requires
Ruby 1.9.1 so a specific ruby version package must be specified.

1. `sudo apt-get install ruby1.9.1 ruby1.9.1-dev zlib1g-dev`
2. `sudo gem install bundler`
3. `git clone https://github.com/chrisvire/BuildUpdate`
4. `cd BuildUpdate`
5. `bundle install`

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
