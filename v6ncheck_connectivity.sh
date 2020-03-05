#!/bin/bash

#################################################################################################
#
# This program will use various means to check status of a managed node. It will:
# 1. Attempt to ping the server, reporting UP, DOWN, or BADADDRESS
# 2. Attempt to determine both the FQDN and IP address of server using nslookup
# 3. Attempt to check TCP port 383 connectivity using netcat, reporting SUCCEEDED, REFUSED, or TIMEOUT
# 4. Attempt to run bbcutil -ping to determing agent health, reporting status and agent version
#
# 22-Feb-2018   Nathan Ellsworth        Radically modified to perform OMi 
#                                        agent check
#
# 
#################################################################################################

verbose=0     # default to CSV output
timeout=2     # default ping timeout
default_infile="hosts.txt"   # default input file
outfile="/dev/stdout" # default output file

# usage - print the usage message
#
usage() {
	echo >&2 "This program will use various means to check status of a managed node. It will:
1. Attempt to ping the server, reporting UP, DOWN, or BADADDRESS
2. Attempt to determine both the FQDN and IP address of server using host command
3. Attempt to check TCP port 383 connectivity using netcat, reporting SUCCEEDED, REFUSED, or TIMEOUT
4. Attempt to run bbcutil -ping to determing agent health, reporting status and agent version

USAGE: $0 [-vch][-t secs][-i inputfile | hosts ...][-o outputfile]

  eg,  $0                     # Check hosts.txt, output to stdout, CSV format
       $0 -v                  # Same as above, but verbose format
       $0 server1 server2     # Check server1&2, output to stdout, verbose format
       $0 -c server1 server2  # Same as above, but CSV format
       $0 -i in.txt -o out.out # Check hosts in in.txt, CSV output to out.out
       $0 -t 60               # Change ping and bbcutil timout to 60 secs (default is 2)"
}

#
# --- Parse Options ---
#
set -- `getopt vcht:i:o: $*`
if [ $? -ne 0 ]; then
        usage
        exit 1
fi

while [ $# -ne 0 ]
do
	case "$1" in
	-v)	verbose=1 
		;;
	-c)	verbose=0 
		;;
	-h)	usage
		exit 0
		;;
	-t)	timeout=$2
		shift
		;;
	-o)	outfile=$2
		touch $outfile
		if [ $? -ne 0 ]; then
		   echo >&2 "ERROR3: output file $outfile, is not writable."
		   exit 2
		fi
                > $outfile
		shift
		;;
	-i)	infile=$2
		if [ ! -r $infile ]; then
		   echo >&2 "ERROR5: $infile, is not readable."
		   exit 2
		fi
		hosts=`cat $infile` 	# Use infile for list of hosts
		shift
		;;
	--)	shift
		break
		;;
	esac
	shift
done

if [ "$1" != "" ]; then			# hosts were on the command line
        hosts=$*
fi

if [ "$hosts" = "" ]; then		# or, fetch hosts from default
	if [ ! -r "$default_infile" ]; then
	   echo >&2 "ERROR6: $default_infile, is not readable."
	   exit 2
	fi
	hosts=`cat $default_infile`
fi

# Output CSV header
if [ $verbose -eq 0 ]; then
    echo Server,Ping,FQDN,IP,PortCheck,BBCPing,AgentVer &>> $outfile
fi

for server in $hosts
do
  if [ $verbose -eq 1 ]; then 
    echo "Testing for server $server" &>> $outfile
  fi

# Ping server once using timeout and capture results
  pingv4=$(ping -q -c 1 -w $timeout $server 2>&1)
  statusv4=$?
  pingv6=$(ping6 -q -c 1 -w $timeout $server 2>&1)
  statusv6=$?
  if [ $statusv4 -eq 2 ]; then output="$pingv6"
  else
    output="$pingv4"
  fi
  ping_check=$(echo "$output" | awk '
   / 0% packet loss/      { up="true" } 
   /unknown host/ { bad="true" } 
   END { if (bad)         { print "BADHOSTNAME" } 
         else if (up)     { print "UP" } 
         else             { print "DOWN" }
   } ')

# Use getent hosts  command to try to determine FQDN and IP address for server
#  fqdn=$(nslookup $server | awk '/name =|Name:/ { print $NF }')
#  ip=$(nslookup $server | awk '/Address/ { print $NF }' | tail -1)

  output=$(getent hosts $server)
  fqdn=$(echo $output | awk '{ print $2 }')
  ip=$(echo $output | awk '{ print $1 }')

# Use netcat to do a port check on BBC port 383
  port_check=$(nc -w 2 -v $server 383 < /dev/null 2>&1 | awk '
    /succeeded/ {print "SUCCEEDED"} 
    /refused/ {print "REFUSED"} 
    /timed out/ {print "TIMEOUT"}')

# Run bbcutil -ping to detect agent connectivity and version if possible
  bbc_ping=$(timeout 1 /opt/OV/bin/bbcutil -ping $server 2>&1 | awk  '
    BEGIN { RS=" "; FS="=" }
    /status/ { status=$2 } 
    /appV/ { ver=$2 }
    END { if (!status) { printf "eHostUnavailable," }
          else         { printf("%s,%s",status,ver) } 
      }
')

# Write verbose output if selected
  if [ $verbose -eq 1 ]; then 
  echo Ping: $ping_check &>> $outfile
  echo FQDN: $fqdn &>> $outfile
  echo IP: $ip &>> $outfile
  echo PortCheck: $port_check &>> $outfile
  echo BBCPing: $bbc_ping &>> $outfile
  echo ------------------------------------------ &>> $outfile
  echo &>> $outfile
  else 
# Othewise create CSV output
   echo $server,$ping_check,$fqdn,$ip,$port_check,$bbc_ping &>> $outfile
  fi
done

