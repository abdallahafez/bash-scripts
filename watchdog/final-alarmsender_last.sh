#!/bin/bash
#echo $*
### ALARM SENDER
time.update() {
NOW=`date '+%Y-%m-%d %H:%M'`
ALARM_LOG_TIME=`date '+%Y-%m-%d %H:%M:%S.%3N%z'`
}
time.update
alarm_file="/var/log/wit/mpesa/alarm.log"
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
WDPATH=$PRGDIR
PATH=$WDPATH:$PATH:/usr/local/bin
trapid=${2}  
process=$4
message=$3
object="Services"
TRAPFILE=$5
TRAPIDFILE=$6
WDPATH=$7
PID_hazelcast=`ps -A -o "%u:%p:%a" | grep -v grep | grep HazelcastMemberStarter | grep -v ARCSIGHT | cut -d ":" -f 2`
PID_tomcat=`ps -A -o "%u:%p:%a" | grep -v grep | grep tomcat-juli | grep -v ARCSIGHT | cut -d ":" -f 2 `
alarm_raise() {
                R3=`cat $alarm_file | grep Tomcat_Failed_Startup_01 | tail -n1|grep -v cleared | wc -l `
               if [ "$R3" == "0" ] ; then 
                 echo "$ALARM_LOG_TIME|MINOR|Tomcat_Failed_Startup_01|Service|Tomcat Failed during startup" >> $alarm_file
                fi
}
alarm_clear() {
                R4=`cat $alarm_file | grep Tomcat_Failed_Startup_01 | tail -n1|grep cleared | wc -l `
                if [ "$R4" == "0" ] ; then 
                 echo "$ALARM_LOG_TIME|NORMAL|Tomcat_Failed_Startup_01|Service|Alarm cleared - Tomcat_Failed_Startup_01" >> $alarm_file
                fi
}
network_dump() {
                        echo "Running netstat..."
                        echo "$NOW - netstat dump" >> logs/server.log
                        netstat -anp > logs/netstat-"$NOW".dump
}
java_dump() {
                        SRVC=$1
                        PID=$2
                if [ "$PID" != "" ]; then
                        echo "Running jmap for memory $SRVC histogram dump..."
                        echo "$NOW - $SRVC jmap dump" >> logs/server.log
                        sudo -u tomcat jmap -histo $PID > logs/jmap-$SRVC-"$NOW".dump
                        echo "Getting $SRVC thread dump..."
                        echo "$NOW - $SRVC thread dump" >> logs/server.log
                        sudo -u tomcat jstack -l  $PID  > logs/jstack-$SRVC-"$NOW".dump
                        kill -s QUIT $PID
                        sleep 5
                else
                        echo "$NOW - NO PID found for $SRVC" >> logs/server.log
                fi
}
tomcat_stop() {
   echo "$NOW - Stopping $process..." >> logs/server.log
                /opt/wit/mpesa/scripts/tomcat-shutdown.sh
                # wait until tomcat is stopped
               x=1
                while [ $x -le 11 ];
                do
                  sleep 10
                time.update
           PID_tomcat=`ps -A -o "%u:%p:%a" | grep -v grep | grep tomcat-juli | grep -v ARCSIGHT | cut -d ":" -f 2`
                  if [ "$PID_tomcat" == "" ]; then
                    break
                  fi
                  x=$(( $x + 1 ))
                if [ "$x" == "10" ] ; then 
                  kill -9 -a $PID_tomcat 2>/dev/null
                  echo "$NOW ..killing the tomcat process " >> logs/server.log
                fi 
                if [ "$x" == "11" ] ; then 
                  alarm_raise 
                  echo "$NOW Tomcat could not be shutdown or killed " >> logs/server.log
                fi 

                done
}
                        #########################################
tomcat_startup(){
                echo "Starting Tomcat..."
                systemctl stop hazelcast
                systemctl start hazelcast
                echo "$NOW - restarting hazelcast...." >> logs/server.log
                echo "$NOW - Starting $process...." >> logs/server.log
                /opt/wit/mpesa/scripts/tomcat-startup.sh
}
                        #########################################
tomcat_startup_validation() {
                #new added by L3 
                #Validating the tomcat sartup 
                #ALARM_LOG_TIME=`date '+%Y-%m-%d %H:%M:%S.%3N%z'`
        sdk="/var/log/wit/mpesa/sdk.log"
  x=1
  while [ $x -le 30 ];
        do
        sleep 5
        time.update
        vstartup=`grep "mPESA SDK - Startup completed" $sdk | awk -v date="$ALARM_LOG_TIME" '$0>date ' ` 
        vstartup+=`grep "successfully added to the queue" $sdk| awk -v date="$ALARM_LOG_TIME" '$0>date ' `
                if [ "$vstartup" != "" ]; then
                        alarm_clear
                        echo "$ALARM_LOG_TIME The tomcat sartup is completed " >> logs/server.log
                        echo "Clearing $process Alarm $trapid: $message"
                        echo "$ALARM_LOG_TIME|NORMAL|$process|$object|$message" >> logs/watchdog-alarm.log
                        cat $WDPATH/$TRAPFILE | grep -v "$1;" > $WDPATH/$TRAPFILE 2> /dev/null 
                        exit  
                fi
                x=$(( $x + 1 ))
                if [ "$x" == "30" ] ; then
                  alarm_raise
                  echo "$NOW Tomcat failed to start within 2:30 minutes " >> logs/server.log
                fi
                done

}
##############################################################################################
#the three stats for tomcat should end with exit 
        if [ "$process" == "tomcat" ]; then
                if [ "${1}" == "raise" ]; then
                        network_dump            
                        java_dump tomcat $PID_tomcat 
                        java_dump hazelcast $PID_hazelcast
                        tomcat_stop             
                        tomcat_startup
                        tomcat_startup_validation
                else
                       network_dump            
                        java_dump tomcat $PID_tomcat 
                        java_dump hazelcast $PID_hazelcast
                        tomcat_startup_validation
                        tomcat_stop             
                        tomcat_startup
                        tomcat_startup_validation
                fi
                exit
        fi
  
if [ "${1}" == "clear" ]; then
        echo "Clearing $process Alarm $trapid: $message"
        echo "$ALARM_LOG_TIME|NORMAL|$process|$object|$message" >> logs/watchdog-alarm.log
else
                if [ "${1}" == "raise" ]; then
                        echo "Raising $process Alarm $trapid: $message"
                        echo "$ALARM_LOG_TIME|CRITICAL|$process|$object|$message" >> logs/watchdog-alarm.log
                else
                        echo "Alarm for $process (Alarm $trapid: $message) already raised. Retrying servers restart." >> logs/watchdog-alarm.log
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
