#!/bin/bash

current_path=`pwd`
case "`uname`" in
    Linux)
		bin_abs_path=$(readlink -f $(dirname $0))
		;;
	*)
		bin_abs_path=`cd $(dirname $0); pwd`
		;;
esac

base=${bin_abs_path}/..
jaas_conf=$base/conf/jaas.conf

export LANG=en_US.UTF-8
export BASE=$base

if [ -f $base/bin/adapter.pid ] ; then
	echo "found adapter.pid , Please run stop.sh first ,then startup.sh" 2>&2
    exit 1
fi

if [ ! -d $base/logs ] ; then
	mkdir -p $base/logs
fi

## set java path
if [ -z "$JAVA" ] ; then
  JAVA=$(which java)
fi

ALIBABA_JAVA="/usr/alibaba/java/bin/java"
TAOBAO_JAVA="/opt/taobao/java/bin/java"
if [ -z "$JAVA" ]; then
  if [ -f $ALIBABA_JAVA ] ; then
  	JAVA=$ALIBABA_JAVA
  elif [ -f $TAOBAO_JAVA ] ; then
  	JAVA=$TAOBAO_JAVA
  else
  	echo "Cannot find a Java JDK. Please set either set JAVA or put java (>=1.5) in your PATH." 2>&2
    exit 1
  fi
fi

case "$#"
in
0 )
  ;;
2 )
  if [ "$1" = "debug" ]; then
    DEBUG_PORT=$2
    DEBUG_SUSPEND="n"
    JAVA_DEBUG_OPT="-Xdebug -Xnoagent -Djava.compiler=NONE -Xrunjdwp:transport=dt_socket,address=$DEBUG_PORT,server=y,suspend=$DEBUG_SUSPEND"
  fi
  ;;
* )
  echo "THE PARAMETERS MUST BE TWO OR LESS.PLEASE CHECK AGAIN."
  exit;;
esac

JavaVersion=`$JAVA -version 2>&1 |awk 'NR==1{ gsub(/"/,""); print $3 }' | awk  -F '.' '{print $1}'`
str=`file -L $JAVA | grep 64-bit`

JAVA_OPTS="$JAVA_OPTS -Xss1m -XX:+AggressiveOpts -XX:-UseBiasedLocking -XX:-OmitStackTraceInFastThrow -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=$base/logs"
if [ $JavaVersion -ge 11 ] ; then
  #JAVA_OPTS="$JAVA_OPTS -Xlog:gc*:$base_log/gc.log:time "
  JAVA_OPTS="$JAVA_OPTS"
else
  #JAVA_OPTS="$JAVA_OPTS -Xloggc:$base/logs/canal/gc.log -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCApplicationStoppedTime"
  JAVA_OPTS="$JAVA_OPTS -XX:+UseFastAccessorMethods -XX:+PrintAdaptiveSizePolicy -XX:+PrintTenuringDistribution"
fi

if [ -n "$str" ]; then
  if [ $JavaVersion -ge 11 ] ; then
    # For G1
    JAVA_OPTS="-server -Xms2g -Xmx3g -XX:+UseG1GC -XX:MaxGCPauseMillis=250 -XX:+UseGCOverheadLimit -XX:+ExplicitGCInvokesConcurrent $JAVA_OPTS"
  else
	  JAVA_OPTS="-server -Xms2g -Xmx3g -Xmn1g -XX:SurvivorRatio=2 -XX:PermSize=96m -XX:MaxPermSize=256m -XX:MaxTenuringThreshold=15 -XX:+DisableExplicitGC $JAVA_OPTS"
	fi
else
	JAVA_OPTS="-server -Xms1024m -Xmx1024m -XX:NewSize=256m -XX:MaxNewSize=256m -XX:MaxPermSize=128m $JAVA_OPTS"
fi

JAVA_OPTS=" $JAVA_OPTS -Djava.awt.headless=true -Djava.net.preferIPv4Stack=true -Dfile.encoding=UTF-8"
ADAPTER_OPTS="-DappName=canal-adapter"
if [ -f "$jaas_conf" ]; then
  ADAPTER_OPTS="$ADAPTER_OPTS -Djava.security.auth.login.config=$jaas_conf"
fi

for i in $base/lib/*;
    do CLASSPATH=$i:"$CLASSPATH";
done

CLASSPATH="$base/conf:$CLASSPATH";

echo "cd to $bin_abs_path for workaround relative path"
cd $bin_abs_path

echo CLASSPATH :$CLASSPATH
$JAVA $JAVA_OPTS $JAVA_DEBUG_OPT $ADAPTER_OPTS -classpath .:$CLASSPATH com.alibaba.otter.canal.adapter.launcher.CanalAdapterApplication 1>>/dev/null 2>&1 &
echo $! > $base/bin/adapter.pid

echo "cd to $current_path for continue"
cd $current_path
