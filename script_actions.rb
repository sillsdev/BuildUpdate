class ScriptActions
  attr_accessor :download_app
  @download_app = 'auto'
  @@subclasses = {}
  def self.create(type)
    c = @@subclasses[type.to_sym]
    if c
      c.new
    else
      raise "Bad script file type: #{type}"
    end
  end

  def self.register_script(name)
    @@subclasses[name] = self
  end

  def file_header
    ''
  end

  def begin_lines
    ''
  end

  def end_lines
    comment('End of script')
  end

  def comment_prefix
    raise 'Not Implemented!'
  end

  def comment(str)
    comment_prefix + ' ' + str
  end

  def mkdir(dir)
    raise 'Not Implemented!'
  end

  def rmdir(dir)
    raise 'Not Implemented!'
  end

  def rm(file)
    raise 'Not Implemented!'
  end

  def variable(var, value)
    comment_prefix + " #{var}=#{value}"
  end

  def parse_variable(line)
    m = /#{comment_prefix}([^=]+)=(.*)$/.match(line)
    unless m.nil? || m.length < 2
      { m[1].strip.to_sym => m[2].strip}
    end
  end

  def curl_update(src, dst)
    "curl -# -L -z #{dst} -o #{dst} #{src}"
  end

  def curl_replace(src, dst)
    "curl -# -L -o #{dst} #{src}"
  end

  def wget_update(src, dst)
    "wget -q -L -N #{src}"
  end

  def unzip(zip_file, dst)
    "unzip -uqo #{zip_file} -d #{dst}"
  end
end

class BashScriptActions < ScriptActions
  def file_header
    '#!/bin/bash'
  end

  def begin_lines
    <<-eos

cd "$(dirname "$0")"

#{comment("*** Functions ***")}
#{functions}
    eos
  end

  def functions
<<-eos
force=0
clean=0

while getopts fc opt; do
case $opt in
f) force=1 ;;
c) clean=1 ;;
esac
done

shift $((OPTIND - 1))

copy_auto() {
if [ "$clean" == "1" ]
then
echo cleaning $2
rm -f ""$2""
else
where_curl=$(type -P curl)
where_wget=$(type -P wget)
if [ "$where_curl" != "" ]
then
copy_curl $1 $2
elif [ "$where_wget" != "" ]
then
copy_wget $1 $2
else
echo "Missing curl or wget"
exit 1
fi
fi
}

copy_curl() {
echo "curl: $2 <= $1"
if [ -e "$2" ] && [ "$force" != "1" ]
then
#{curl_update('$1', '$2')}
else
#{curl_replace('$1', '$2')}
fi
}

copy_wget() {
echo "wget: $2 <= $1"
f=$(basename $2)
d=$(dirname $2)
cd $d
#{wget_update('$1', '$f')}
cd -
}
eos
  end

  def comment_prefix
    '#'
  end

  def unix_path(dir)
    dir.gsub!('\\','/')
    unless dir[/\s+/].nil?
      dir = "\"#{dir}\""
    end

    dir
  end

  def mkdir(dir)
    "mkdir -p #{unix_path(dir)}"
  end

  def rmdir(dir)
    "rm -rf #{unix_path(dir)}"
  end

  def rm(file)
    "rm -rf #{unix_path(file)}"
  end

  def download(src,dst)
    "copy_#{@download_app} #{src} #{unix_path(dst)}"
  end

  register_script :sh
end

class CmdScriptActions < ScriptActions
  def file_header
    '@echo off'
  end

  def begin_lines
    <<-eos
setlocal EnableDelayedExpansion
pushd "%~dp0"
:getopts
if "%~1" == "-f" SET FORCE_DOWNLOAD=1
if "%~1" == "-c" SET CLEAN_DOWNLOAD=1
shift
if not "%~1" == "" goto getopts
    eos
  end
  def end_lines
    "endlocal\npopd\ngoto:eof\n\n" + functions + comment('End of Script')
  end

  def functions
    <<-eos
:copy_auto
if "!CLEAN_DOWNLOAD!" == "1" (
echo. cleaning %2
DEL /F %2
) ELSE (
if "!USE_CURL!!USE_WGET!" == "" (
curl --help >nul 2>&1
if !errorlevel! == 0 (
SET USE_CURL=1
) ELSE (
wget --help >nul 2>&1
if !errorlevel! == 0 (
SET USE_WGET=1
) ELSE (
echo. curl and wget are missing!
exit /b
)
)
)
if !USE_CURL! == 1 (
call :copy_curl %1 %2
) ELSE (
IF !USE_WGET! == 1 (
call :copy_wget %1 %2
)
)
)
goto:eof

:copy_curl
echo. %~2
echo. %~1
if exist %~2 if "!FORCE_DOWNLOAD!" == "" (
#{curl_update('%~1', '%~2')}
) else (
#{curl_replace('%~1', '%~2')}
)
goto:eof

:copy_wget
echo. %~2
echo. %~1
pushd %~2\\..\\
#{wget_update('%~1', '%~2')}
popd
goto:eof
    eos
  end

  def comment_prefix
    '::'
  end

  def windows_path(dir)
    dir.gsub!('/', '\\')
    unless dir[/\s+/].nil?
      dir = "\"#{dir}\""
    end

    dir
  end

  def mkdir(dir)
    win_dir = windows_path(dir)
    "if not exist #{win_dir}\\nul mkdir #{win_dir}"
  end

  def rmdir(dir)
    win_dir = windows_path(dir)
    "del /f/s/q #{win_dir}"
    "rmdir #{win_dir}"
  end

  def rm(file)
    "del /f/s/q #{windows_path(file)}"
  end

  def download(src,dst)
    "call:copy_#{@download_app} #{src} #{windows_path(dst)}"
  end

  register_script :bat
end
