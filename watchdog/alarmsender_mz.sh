#!/bin/bash
#echo $*
### ALARM SENDER
NOW=`date '+%Y-%m-%d %H:%M'`

ALARM_LOG_TIME=`date '+%Y-%m-%d %H:%M:%S.%3N%z'`

# resolve links - $0 may be a softlink
PRG="$0"
while [ -h "$PRG" ]; do
        ls=`ls -ld "$PRG"`
        link=`expr "$ls" : '.*-> \(.*\)$'`
        if expr "$link" : '/.*' > /dev/null; then
                PRG="$link"
        else
                PRG=`dirname "$PRG"`/"$link"
        fi
done

trapid=${2}  
process=$4
message=$3
object="Services"

if [ "${1}" == "clear" ]; then
        echo "Clearing $process Alarm $trapid: $message"
		echo "$ALARM_LOG_TIME|NORMAL|$process|$object|$message" >> logs/watchdog-alarm.log
else
		if [ "${1}" == "raise" ]; then
			echo "Raising $process Alarm $trapid: $message"
			echo "$ALARM_LOG_TIME|CRITICAL|$process|$object|$message" >> logs/watchdog-alarm.log
		else
			echo "Alarm for $process (Alarm $trapid: $message) already raised. Retrying servers restart."
		fi
		
        if [ "$process" == "tomcat" ]; then
                PID=`ps -A -o "%u:%p:%a" | grep -v grep | grep tomcat-juli | grep -v ARCSIGHT | cut -d ":" -f 2`

                if [ "$PID" != "" ]; then

                        echo "Running netstat..."
                        echo "$NOW - netstat dump" >> logs/server.log
                        netstat -anp > logs/netstat-"$NOW".dump

                        echo "Running jmap for memory histogram dump..."
                        echo "$NOW - jmap dump" >> logs/server.log
                        sudo -u tomcat jmap -histo $PID > logs/jmap-"$NOW".dump

                        echo "Getting tomcat thread dump..."
                        echo "$NOW - Tomcat thread dump" >> logs/server.log
                        sudo -u tomcat jstack -l  $PID  > logs/jstack-"$NOW".dump
                        kill -s QUIT $PID
                        sleep 5
                fi
                echo "$NOW - Stopping $process..." >> logs/server.log

                /opt/wit/mpesa/scripts/tomcat-shutdown.sh

                # wait until tomcat is stopped
                x=1
                while [ $x -le 10 ];
                do
                  sleep 10

                  PID=`ps -A -o "%u:%p:%a" | grep -v grep | grep tomcat-juli | grep -v ARCSIGHT | cut -d ":" -f 2`

                  if [ "$PID" == "" ]; then
                    break
                  fi

                  x=$(( $x + 1 ))
                done

                if [ "$PID" != "" ]; then
                  kill -9 -a $PID 2>/dev/null
                fi

                echo "Starting Tomcat..."
                echo "$NOW - Starting $process...." >> logs/server.log
                /opt/wit/mpesa/scripts/tomcat-startup.sh
        fi

        if [ "$process" == "apache" ]; then

                echo "$NOW - Stopping $process..." >> logs/server.log

                /opt/wit/mpesa/scripts/httpd-shutdown.sh

                sleep 10

                echo "Starting httpd..." >> logs/server.log
                echo "$NOW - Starting $process...."

                /opt/wit/mpesa/scripts/httpd-startup.sh   
        fi
fi
