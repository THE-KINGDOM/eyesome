#!/bin/bash

# NAME: eyesome-src.sh
# PATH: /usr/local/bin
# DESC: Source (include) file for eyessome.sh, eyesome-sun.sh, eyesome-cfg.sh,
#       wake-eyesome.sh and acpi-lid-eyesome.sh.
# CALL: Include at program top with `. eyesome-src` or `source eyesome-src`.
# NOTE: You do not have to specify directory because $PATH is searched.
#       This will not work with shebang #!/bin/sh it MUST be #!/bin/bash

# DATE: Feb 17, 2017. Modified: Sep 29, 2018.

OLD_IFS=$IFS
IFS="|"

declare -a CfgArr

CFG_SUNCITY_NDX=0
CFG_SLEEP_NDX=1
CFG_AFTER_SUNRISE_NDX=2
CFG_BEFORE_SUNSET_NDX=3
CFG_TEST_SECONDS_NDX=4
# 6 spare fields
CFG_MON1_NDX=10
CFG_MON2_NDX=30
CFG_MON3_NDX=50
CFG_LAST_NDX=69
CFG_CURR_BRIGHTNESS_OFFSET=14
CFG_CURR_GAMMA_OFFSET=15

ConfigFilename=/usr/local/bin/.eyesome-cfg
SunsetFilename=/usr/local/bin/.eyesome-sunset
SunriseFilename=/usr/local/bin/.eyesome-sunrise
EyesomeDaemon=/usr/local/bin/eyesome.sh
CurrentBrightnessFilename=/tmp/display-current-brightness
CronStartEyesome=/etc/cron.d/start-eyesome
CronSunHours=/etc/cron.daily/daily-eyesome-sun
EyesomeSunProgram=/usr/local/bin/eyesome-sun.sh
WakeEyesome=/usr/local/bin/wake-eyesome.sh
SystemdWakeEyesome=/lib/systemd/system-sleep/systemd-wake-eyesome
EyesomeIsSuspending=/tmp/eyesome-is-suspending
log() {

    # Wrapper script for logger command

    # PARM: $1 Message to print
    #       $$=pid of bash script
    #       $0=name of bash scxript
    #       $#=Number of paramters passed
    
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    Basename="$0"
    Basename="${Basename##*/}"

    case $Basename in
        eyesome.sh)
            ScriptName=Daemon;;
        wake-eyesome.sh)
            # Three pgorams can call, how to narrow down? pstree?
            ScriptName=Wakeup;;
        acpi-lid-eyesome.sh)
            ScriptName="Lid Open/Close";;
        eyesome-cfg.sh)
            ScriptName=Setup;;
        eyesome-sun.sh)
            ScriptName="Sun Times";;
        *)
            ScriptName="eyesome-src.sh Function: log() - unknown name";;
    esac

    if [ $# -ne 1 ]; then
        Msg="eyesome-src.sh Function: log() wrong number of parameters: $#"
    else
        Msg="$1"
    fi

    logger --id=$$ -t "eyesome" "$ScriptName: $Msg"

} # log

# Monitor working storage
GetMonitorWorkSpace () {

    # Move configuration array monitor 1-3 to WorkSpace fields
    # $1 = CfgArr Starting Index Number
    
    i=$1
    MonNumber="${CfgArr[$((i++))]}"          # "1", "2" or "3"
    MonStatus="${CfgArr[$((i++))]}"          # "Enabled" / "Disabled"
    MonType="${CfgArr[$((i++))]}"            # "Hardware" / "Software"
    MonName="${CfgArr[$((i++))]}"            # "Laptop Display" / '50" Sony TV'
    MonHardwareName="${CfgArr[$((i++))]}"    # "intel_backlight" / "xrandr"
    MonXrandrName="${CfgArr[$((i++))]}"      # "eDP-1-1" (primary) / "HDMI-0", etc
    MonDayBrightness="${CfgArr[$((i++))]}"   # often half of real maximum brightness
    MonDayRed="${CfgArr[$((i++))]}"          # yad uses 6 decimal places. Gamma
    MonDayGreen="${CfgArr[$((i++))]}"        # broken down between Red:Green:Blue
    MonDayBlue="${CfgArr[$((i++))]}"         # built into single string
    MonNgtBrightness="${CfgArr[$((i++))]}"
    MonNgtRed="${CfgArr[$((i++))]}"
    MonNgtGreen="${CfgArr[$((i++))]}"
    MonNgtBlue="${CfgArr[$((i++))]}"
    MonCurrBrightness="${CfgArr[$((i++))]}"
    MonCurrGamma="${CfgArr[$((i++))]}"
    # 4 spare fields

} # GetMonitorWorkSpace


# Monitor working storage
SetMonitorWorkSpace () {

    # Move WorkSpace 1-3 into array for writing to disk
    # $1 = CfgArr Starting Index Number
    i=$1

    CfgArr[$((i++))]="$MonNumber"           # "1", "2" or "3"
    CfgArr[$((i++))]="$MonStatus"           # "Enabled" / "Disabled"
    CfgArr[$((i++))]="$MonType"             # "Hardware" / "Software"
    CfgArr[$((i++))]="$MonName"             # "Laptop Display" / '50" Sony TV'
    CfgArr[$((i++))]="$MonHardwareName"     # "intel_backlight" / "xrandr"
    CfgArr[$((i++))]="$MonXrandrName"       # "eDP-1-1" (primary) / "HDMI-0", etc
    CfgArr[$((i++))]="$MonDayBrightness"    # often half of real maximum brightness
    CfgArr[$((i++))]="$MonDayRed"           # yad uses 6 decimal places. Gamma
    CfgArr[$((i++))]="$MonDayGreen"         # broken down between Red:Green:Blue
    CfgArr[$((i++))]="$MonDayBlue"          # built into single string
    CfgArr[$((i++))]="$MonNgtBrightness"
    CfgArr[$((i++))]="$MonNgtRed"
    CfgArr[$((i++))]="$MonNgtGreen"
    CfgArr[$((i++))]="$MonNgtBlue"
    CfgArr[$((i++))]="$MonCurrBrightness"
    CfgArr[$((i++))]="$MonCurrGamma"
    # 4 spare fields

} # SetMonitorWorkSpace

declare aXrandr=()

InitXrandrArray () {

    # Array is used for each monitor and searched by name.
    # Save time to search on connected/disconnected, primary monitor,
    # brightness level, gamma level.

    mapfile -t aXrandr < <(xrandr --verbose --current)
    
} # InitXrandrArray

SearchXrandrArray () {

    # Parms: $1 = xrandr monitor name to search for.

    # NOTE: Entries in array follow predicatble order from xrandr --verbose:

    #       <MONITOR-NAME> connected / disconnected (line 1 of monitor entry)
    #       Gamma:      0.99:0.99:0.99              (line 5 of entry)
    #       Brightness: 0.99                        (line 6 of entry)
    #       CRTC:       9                           (line 8 of entry)

    fNameFnd=false
    fBrightnessFnd=false
    fGammaFnd=false
    fCrtcFnd=false
    XrandrConnection=disconnected
    XrandrPrimary=false
    XrandrGamma=""
    XrandrBrightness=""
    XrandrCRTC=""           # Laptop lid open value=0, lid closed=blank

    for (( i=0; i<"${#aXrandr[*]}"; i++ )) ; do

        line="${aXrandr[$i]}"
        # Have we looped to next monitor and not found search string?
        if [[ "$line" =~ " connected " ]] && [[ $fNameFnd == true ]] ; then
            break
        fi

        if [[ "$line" =~ ^"$MonXrandrName connected" ]]; then
            fNameFnd=true
            XrandrConnection=connected
            [[ "$line" =~ "primary" ]] && XrandrPrimary=true
        fi

        if [[ $fNameFnd == true ]] && [[ $fGammaFnd == false ]] ; then
            if [[ "$line" =~ "Gamma: " ]]; then
                fGammaFnd=true
                XrandrGamma="${line##* }"
                # TODO: Use `xgamma` for accuracy
            fi
        fi

        if [[ $fGammaFnd == true ]] && [[ $fBrightnessFnd == false ]] ; then
            if [[ "$line" =~ "Brightness: " ]]; then
                fBrightnessFnd=true
                XrandrBrightness="${line##* }"
            fi
        fi

        if [[ $fBrightnessFnd == true ]] && [[ $fCrtcFnd == false ]] ; then
            if [[ "$line" =~ "CRTC: " ]]; then
                fCrtcFnd=true
                XrandrCRTC="${line##* }"
                break
            fi
        fi
        
    done
    
} # SearchXrandrArray

CreateConfiguration () {

    # Initialize array to blanks because we have spare fields for future
    for ((i=0; i<=CFG_LAST_NDX; i++)); do
        CfgArr[$i]=" "
    done
    
    # When you type https://www.timeanddate.com/worldclock the second link
    # is your default country/city name. For `grep` parameter credits see:
    #    https://unix.stackexchange.com/questions/146749/grep-substring-between-quotes
    
    SunCity=$(wget -q -O- https://www.timeanddate.com/worldclock | grep -oP \
        '<div class=my-city__items><div class=my-city__item><a href="\K[^"]+' )

    # Change $SunCity from:  /worldclock/country/city
    #                   to:  https://www.timeanddate.com/sun/country/city
    
    SunCity="${SunCity/\/worldclock/https:\/\/www.timeanddate.com\/sun}"
    CfgArr[$CFG_SUN_NDX]="$SunCity"
    CfgArr[$CFG_SLEEP_NDX]=60
    CfgArr[$CFG_BEFORE_SUNSET_NDX]=90
    CfgArr[$CFG_AFTER_SUNRISE_NDX]=120
    CfgArr[$CFG_TEST_SECONDS_NDX]=5

    # Deafult Daytime brightness
    backlight=$(ls /sys/class/backlight)
    # If no hardware support use software, eg `xrandr`
    MonStatus="Enabled"                 # opposite is "Disabled"
    if [[ $backlight == "" ]]; then
        # No /sys/class/backlight/* directory so software controlled (xrandr)
        MonType="Software"
        MonName="xrandr controlled"
        backlight="xrandr"
        MonDayBrightness="1.000000"     # yad uses 6 decimal places
    else
        MonType="Hardware"
        MonName="Laptop Display"
        # Current user set brightness level will be max brightness for us
        MonDayBrightness=$(cat "/sys/class/backlight/$backlight/brightness")
    fi

    # Set Monitor 1 fields based on "primary" setting in xrandr
    MonHardwareName="$backlight"
    XrandrName=$(xrandr --current | grep primary)
    PrimaryMonitor=${XrandrName%% *}
    MonXrandrName="$PrimaryMonitor"     # "eDP-1-1" "LVDS1", etc.

    MonDayRed="1.000000"                # yad uses 6 decimal places. Gamma
    MonDayGreen="1.000000"              # broken down between Red:Green:Blue
    MonDayBlue="1.000000"               # built into single string
    MonDayGamma="$MonDayRed:$MonDayGreen:$MonDayBlue" # Not stored, just habit
    MinAfterSunrise="120"
    MinBeforeSunset="120"
    MonNgtBrightness="$MonDayBrightness"
    MonNgtRed="$MonDayRed"
    MonNgtGreen="$MonDayGreen"
    MonNgtBlue="$MonDayBlue"
    MonNgtGamma="$MonDayGamma"
    MinBeforeSunset="$MinAfterSunrise"
    MonCurrBrightness="$MonDayBrightness"
    MonCurrGamma="$MonDayGamma"
    
    MonNumber=1                         # others = "2" or "3"
    SetMonitorWorkSpace $CFG_MON1_NDX   # Set Monitor #1

    # Set Monitor 2 based on next non-primary and active monitor in xrandr    
    MonNumber=2
    MonType="Software"
    MonHardwareName="xrandr"
    MonName="xrandr controlled"
    MonDayBrightness="1.000000"
    MonNgtBrightness="$MonDayBrightness"
    MonCurrBrightness="$MonDayBrightness"
    
    XrandrName=$(xrandr --current | grep -v "$PrimaryMonitor" | grep -v dis | \
                grep connected )
    Monitor2=${XrandrName%% *}
    MonXrandrName="$Monitor2"
    
    # If Monitor2 blank no external TV / monitor attached
    if [[ "$Monitor2" == "" ]]; then MonStatus="Disabled"
                                else MonStatus="Enabled" ; fi

    SetMonitorWorkSpace $CFG_MON2_NDX   # Set Monitor #2
    
    # Set Monitor 3 based on next monitor in xrandr that isn't Monitor 1 or 2.
    MonNumber=3
    
    XrandrName=$(xrandr --current | grep -v "$PrimaryMonitor" | grep -v dis | \
                grep -v "$Monitor2" | grep connected )
    Monitor3=${XrandrName%% *}
    MonXrandrName="$Monitor3"
    
    # If Monitor2 blank no external TV / monitor attached
    if [[ "$Monitor3" == "" ]]; then MonStatus="Disabled"
                                else MonStatus="Enabled" ; fi

    SetMonitorWorkSpace $CFG_MON3_NDX   # Set Monitor #3

} # CreateConfiguration

ReadConfiguration () {

    # Read hidden configuration file with entries separated by "|" into array
    if [[ -s "$ConfigFilename" ]] ; then
         IFS='|' read -ra CfgArr < "$ConfigFilename"
    else CreateConfiguration ; fi
    
    # If sunrise/set files missing, use default values
    if [[ -s "$SunriseFilename" ]]; then sunrise=$(cat "$SunriseFilename")
                                    else sunrise="6:32 am" ; fi
    
    if [[ -s "$SunsetFilename" ]];  then sunset=$(cat "$SunsetFilename")
                                    else sunset="8:37 pm" ; fi    

    SunHoursAddress="${CfgArr[CFG_SUNCITY_NDX]}"
    # cut yad's 6 decimal positions using "%.*"
    UpdateInterval="${CfgArr[CFG_SLEEP_NDX]%.*}"
    MinAfterSunrise="${CfgArr[CFG_AFTER_SUNRISE_NDX]%.*}"
    MinBeforeSunset="${CfgArr[CFG_BEFORE_SUNSET_NDX]%.*}"
    TestSeconds="${CfgArr[CFG_TEST_SECONDS_NDX]%.*}"

    # Internal array of Xrandr all setings for faster searches
    aXrandr=( $(xrandr --verbose --current) )

} # ReadConfiguration

WriteConfiguration () {

    # write hidden configuration file using array
    echo "${CfgArr[*]}" > "$ConfigFilename"

} # WriteConfiguration

CalcNew () {

    # Sets NewReturn to new value
    # Parm: 1= Source Value (9999.999999)
    #       2= Target Value (9999.999999)
    #       3= Progress .999999 in six decimals. At start of transition
    #          progress is .000001 & nearing end of transition it is .999999

    st=$(echo "$1 < $2" | bc)

    if [[ $st -eq 1 ]] ; then
        # Target >= Source
        Diff=$( bc <<< "scale=6; $2 - $1" )
        Diff=$( bc <<< "scale=6; $Diff * $3" )
        NewReturn=$( bc <<< "scale=6; $1 + $Diff" )
    else
        # Target < Source
        Diff=$( bc <<< "scale=6; $1 - $2" )
        Diff=$( bc <<< "scale=6; $Diff * $3" )
        NewReturn=$( bc <<< "scale=6; $2 + $Diff" )
    fi

} # CalcNew

CalcBrightness () {

    # Parms $1=Day / Night
    #       $2=Adjust factor (percentage in .999999)
    #       If $2 not passed then return Day or Night value without adjustment

    NewGamma=""
    NewBrightness=""
    
    if [[ $1 == Day ]]; then
        # Fixed Daytime setting or transitioning to Daytime
        if [[ -z "$2" ]]; then
            # Parameter 2 is empty so no adjustment percentage (no transition)
            NewGamma="$MonDayRed:$MonDayGreen:$MonDayBlue"
            NewBright="$MonDayBrightness"
        else
            CalcNew $MonNgtRed $MonDayRed $2
            NewRed=$NewReturn
            CalcNew $MonNgtGreen $MonDayGreen $2
            NewGreen=$NewReturn
            CalcNew $MonNgtBlue $MonDayBlue $2
            NewBlue=$NewReturn
            NewGamma="$NewRed:$NewGreen:$NewBlue"

            CalcNew $MonNgtBrightness $MonDayBrightness $2
            NewBright=$NewReturn
        fi
    else
        # Fixed Nightime setting or transitioning to Nighttime
        if [[ -z "$2" ]]; then
            NewGamma="$MonNgtRed:$MonNgtGreen:$MonNgtBlue"
            NewBright="$MonNgtBrightness"
        else
            # Parameter 2 passed. Use it as adjustment factor (transitioning).
            CalcNew $MonDayRed $MonNgtRed $2
            NewRed=$NewReturn
            CalcNew $MonDayGreen $MonNgtGreen $2
            NewGreen=$NewReturn
            CalcNew $MonDayBlue $MonNgtBlue $2
            NewBlue=$NewReturn
            NewGamma="$NewRed:$NewGreen:$NewBlue"

            CalcNew $MonDayBrightness $MonNgtBrightness $2
            NewBright=$NewReturn
        fi
    fi

# TODO: Changing sound between monitors can reset brightness.
# Remove comment below to log values to journalctl / syslog
#[[ $MonNumber == "1" ]] && log "Mon #: $MonNumber Day: $MonDayBrightness Ngt: $MonNgtBrightness Curr: $NewBright"

} # CalcBrightness

SetBrightness () {

    # Called from: - eyesome.sh for long day/night sleep NO $2 passed
    #              - eyesome.sh for short transition period $2 IS passed
    #              - eyesome-cfg.sh for short day/night test NO $2 passed

    # Parm: $1 = Day (includes increasing after sunrise when $2 passed)
    #            Ngt (Includes decreasing before sunset when $2 passed)
    #       $2 = % fractional adjustment (6 decimals)
    #       If $2 not passed then use full day or full night values
 
    # Note: Day can be less than night. ie Red Gamma @ Day = 1.0, Ngt = 1.2   

    aMonNdx=( $CFG_MON1_NDX $CFG_MON2_NDX $CFG_MON3_NDX )
    InitXrandrArray
    aAllMon=()      # Used in eyesome-cfg.sh, NOT used in eyesome.sh
    
    for MonNdx in ${aMonNdx[@]}; do
    
        GetMonitorWorkSpace $MonNdx

        # aAllMon used by TestBrightness () in eyesome-cfg.sh
        aAllMon+=("# ")
        aAllMon+=("# Monitor Number: $MonNumber")
        aAllMon+=("# Name: $MonName")
        aAllMon+=("# Status: $MonStatus")
        SearchXrandrArray $MonXrandrName
        aAllMon+=("# Connection: $XrandrConnection")
        aAllMon+=("# Xrandr CRTC: $XrandrCRTC")

        [[ $XrandrConnection == disconnected ]] && continue
        [[ $XrandrCRTC == "" ]] && continue
        [[ $MonStatus == Disabled ]] && continue

        CalcBrightness $1 $2

        if [[ $MonType == "Hardware" ]]; then
            backlight="/sys/class/backlight/$MonHardwareName/brightness"
            Brightness=1.00    # Fake for xrandr below
            FakeXrandrBright=true
            IntBrightness=${NewBright%.*}   # Strip decimals
            DisplayBrightness="$IntBrightness"
        else
            # Software brightness control
            FakeXrandrBright=false
            IntBrightness=0
            Brightness=$(printf %.2f $NewBright)
            DisplayBrightness="$Brightness"
        fi

        # Set software brightness and gamma
        xRetn=$(xrandr --output $MonXrandrName --gamma $NewGamma \
                --brightness $Brightness)

        # Set hardware brightness
        [[ $IntBrightness != 0 ]] && bash -c \
                                    "echo $IntBrightness | sudo tee $backlight"

        # Set current brightness display file (also used for lid close tracking)
        [[ $MonNumber == "1" ]] && echo "$DisplayBrightness" > \
                                        "$CurrentBrightnessFilename"

        # Save current settings to eyesome configuration file
        MonCurrGamma="$NewGamma"
        MonCurrBrightness="$DisplayBrightness"
        SetMonitorWorkSpace "$MonNdx"

    done
    
    WriteConfiguration

} # SetBrightness


