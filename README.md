# BuildUpdate

## Summary
This Ruby scripts manages a bash script that updates the build environment on a 
developer's machine to match the environment used on TeamCity.  The generated
bash script will download the artifact dependencies needed for the project.

## Installation
---
### Windows Install Requirements
* Install bash via [msysgit](http://msysgit.github.io/) (which includes Git Bash) or [Cygwin](http://www.cygwin.com/)
* Install [Ruby](http://rubyinstaller.org/downloads/) -- Use 2.4.4-1 (without devkit) or 2.3.3
  * Check "Add Ruby executables to your PATH"
  * Check "Associate .rb and .rbw files with this Ruby installation"
* `gem install bundler`
* `git clone https://github.com/sillsdev/BuildUpdate`
* `cd BuildUpdate`
* `bundle install`

### Ubuntu 18.04 & 16.04 Install Requirements
The default version of Ruby for Ubuntu 18.04 is 2.5.1
The default version of Ruby for Ubuntu 16.04 is 2.3.1.

1. `sudo apt-get install ruby ruby-dev zlib1g-dev`
2. `sudo gem install bundler`
3. `git clone https://github.com/sillsdev/BuildUpdate`
4. `cd BuildUpdate`
5. `bundle install`

## Authentication
Team City requires authentication to access project configuration.  The script will prompt
for the username and password.  You can specify these in the following environment variables:

```
BUILDUPDATE_USER
BUILDUPDATE_PASSWORD
```

## Setup
BuildUpdate will need to generate a bash script for each platform (e.g. Windows or Linux)
for the project.  There is normally a continuous build setup for each platform.  For example,
browse to http://build.palaso.org and select "libpalaso" project and 
"palaso-precise64-master Continuous" build and the url will be 
http://build.palaso.org/viewType.html?buildTypeId=bt322.  You will see `buildTypeId=XXXXX` 
in the query string.  BuildUpdate refers to this as `build_type` with a value of `bt322`.
   
### Create the shell script
To create the initial shell script, determine the `build_type` and run the following command
(of cource, windows users should used backslashes):

```
cd to/src/repo
../path/to/BuildUpdate/buildupdate.rb -f getDependencies-linux.sh -t YOUR_BUILD_TYPE
```

### Create the shell script in a sub-directory
If the shell script will be in a sub-directory of the project repo, you need to specify
the root directory for where to run the update commands relative to the sub-directory.  
For example, if you you decide to put these shell scripts in the `build` sub-directory,
then run the following command:

```
$ cd to/src/repo/build
$ ../../path/to/BuildUpdate/buildupdate.rb -r .. -f getDependencies-linux.sh -t YOUR_BUILD_TYPE
```

1. Create a buildupdate.sh script in your build directory with configuration (see below).  
2. Run the buildupdate.rb script to update buildupdate.sh with all of the calls to update the current build environment.
3. Commit the buildupdate.sh script to source control.

## Updates
---
### Update scripts when dependencies change
These generated bash scripts should be committed into the source code respository.  If the 
dependencies in Team City change, then the bash scripts need to be updated. Run the following command:

```
$ cd to/src/repo
$ ../../path/to/BuildUpdate/buildupdate.rb -f path/to/getDependencies-linux.sh
```

The Ruby scripts will look at configuration at the top of the bash script to determine
the `build_type` and the `root_dir`.

### Working in a different branch
If you are working in a long-running branch, you might have different dependencies 
that then master `build_type`.  Setup a new `build_type` and commit a bash script to the
branch (and be careful not to push it back to master).
 
## Information
---
### File format

The configuration is in comments at the beginning of the file.  The variables used are: 
* server: specifies the the hostname of the TeamCity Server
* project: the name of the TeamCity project
* build: the name of the TeamCity build configuration
* build_type: the TeamCity buildType id
* root_dir: specify the directory relative to the location of the script where the
commands of the script should be run

### Specifying a build
To specify a build you can either do:
```
$ ../../path/to/BuildUpdate/buildupdate -f getDependencies-linux.sh -t YOUR_BUILD_TYPE
```
Or:
```
$ ../../path/to/BuildUpdate/buildupdate -f getDependencies-linux.sh -p "PROJECT_NAME" -b "BUILD_NAME"
```

Since the `PROJECT_NAME` and `BUILD_NAME` are just labels which can be changed through
the Team City user interface, you should use the `build_type` instead (it doesn't change).

### Getting list of projects from the command line
You can run the ruby script without parameters to get a list of projects.

```
$ ../../path/to/BuildUpdate/buildupdate
You need to specify project!
Possible Names:
  <Root project>
  Adapt It
  Bloom
  BloomLibrary.org
  BloomPlayer
```

Then you can use `-p PROJECT_NAME` to get a list of `build_type : build_name` pairs.

 ```
 $ ../../path/to/BuildUpdate/buildupdate -p Bloom
Missing Build!
Possible 'Build Type : Build Name' pairs:
  BloomReleaseInternal37 : Bloom 3.7 Release Internal
  Bloom_Bloom37linux64Auto : Bloom-3.7-Linux64-Continuous
  bt222 : Bloom-Default-Continuous
  bt403 : Bloom-Default-Linux64-Continuous
  bt430 : Bloom-Master-JS-Tests
  bt396 : bloom-win32-static-dependencies
  BPContinuous : BloomPlayer-Master-Continuous
  bt434 : GtkUtils
  Bloom_Squirrel : Squirrel
  Bloom_YouTrackSharp : YouTrackSharp
```
## Developers
---
Please reports issues through [repo issues](https://github.com/sillsdev/BuildUpdate/issues/).
If you like to contribute, please fork the repo and send pull requests.
I will document debugging tips on the [repo wiki](https://github.com/sillsdev/BuildUpdate/wiki).
