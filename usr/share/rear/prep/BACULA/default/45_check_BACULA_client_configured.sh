#
# Check that bacula is installed and configuration files exist

if [ "$BEXTRACT_DEVICE" -o "$BEXTRACT_VOLUME" ]; then

   ### Bacula support using bextract
   type -p bextract &>/dev/null
   ProgressStopIfError $? "Bacula bextract is missing"

   if [ ! -s /etc/bacula/bacula-sd.conf ]; then
      ProgressStopIfError 1  "Bacula configuration file (bacula-sd.conf) missing"
   fi

else

   ### Bacula support using bconsole
   type -p bacula-fd &>/dev/null
   ProgressStopIfError $? "Bacula File Daemon is missing"

   if [ ! -s /etc/bacula/bacula-fd.conf ]; then
      ProgressStopIfError 1  "Bacula configuration file (bacula-fd.conf) missing"
   fi

   type -p bconsole &>/dev/null
   ProgressStopIfError $? "Bacula console executable is missing"

   if [ ! -s /etc/bacula/bconsole.conf ]; then
      ProgressStopIfError 1  "Bacula configuration file (bconsole.conf) missing"
   fi

fi
