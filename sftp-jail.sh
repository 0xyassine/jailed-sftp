#!/bin/bash

#BY 0xYASSINE

#ROOT ACCESS IS REQUIRED
if [ $UID -ne 0 ];then
  echo "[!] SCRIPT MUST RUN AS ROOT"
  exit
fi

# DISPLAY THE MENU
function display_menu()
{
  echo "USER ACCOUNT MANAGEMENT MENU:"
  echo "1. ADD USER"
  echo "2. ADD GROUP"
  echo "3. DELETE USER"
  echo "4. DELETE GROUP"
  echo "5. ENABLE USER"
  echo "6. DISABLE USER"
  echo "0. EXIT"
}

#VERIFY IF ENTRY EXSIST IN THE FILE AND ADD IT IF NEEDED
function verify_entry()
{
        # $1 IS THE ENTRY FILE
        # $2 IS THE VALUE TO BE ADDED IF NOT IN THE $1
        if ! grep "^$2" "$1" 1>/dev/null;then
                echo "$2" >> $1
                echo "[ $2 ] added to $1"
                return 1
        else
                return 0
        fi
}

# CHECK IF USER IS FOUND
function check_user()
{
  local USER_NAME=$1
  if id "$USER_NAME" &>/dev/null;then
    if cat /etc/passwd | grep -E "^${USER_NAME}\:" | grep "$COMMENT" | grep -q "$USER_NAME" ;then
      #FOUND AND CREATED BY THIS SCRIPT
      return 0
    elif cat /etc/passwd | grep -qE "^${USER_NAME}\:";then
      #FOUND BUT NOT CREATED BY THIS SCRIPT
      return 1
    fi
  else
    #NOT FOUND
    return 2
  fi
}

# CHECK IF GROUP IS FOUND
function check_group()
{
  local GROUP_NAME=$1
  if getent group $GROUP_NAME &>/dev/null;then
    if cat /etc/group | grep "^${GROUP_NAME}\:" | grep "$COMMENT" | grep -q "$GROUP_NAME";then
      #FOUND AND CREATED BY THIS SCRIPT
      return 0
    elif cat /etc/group | grep -qE "^${GROUP_NAME}\:";then
      #FOUND BUT NOT CREATED BY THIS SCRIPT
      return 1
    fi
  else
    #NOT FOUND
    return 2
  fi
}


# ASK FOR CONFIRMATION
function ask()
{
  read -p 'ARE YOU SURE YOU WANT TO CONTINUE (y/n) ' CHOICE
  case $CHOICE in
  y)
    echo "CONTINUE"
    return 0;;
  n)
    echo "ABORTING"
    return 1;;
  *)
    echo "INVALID CHOICE"
    return 2;;
  esac
}

# SET CORRECT PERMISSIONS
function set_permission()
{
  local SFTP_USER_NAME=$1
  local SFTP_GROUP_NAME=$2
  local SFTP_DIR=$3
  SSH_DIR="/home/$SFTP_USER_NAME/.ssh"
  mkdir -p $SSH_DIR
  [[ ! -f $SSH_DIR/authorized_keys ]] && touch $SSH_DIR/authorized_keys
  chmod 600 $SSH_DIR/authorized_keys
  chmod 700 $SSH_DIR/
  chown -R $SFTP_USER_NAME:$SFTP_GROUP_NAME $SSH_DIR
  mkdir -p $SFTP_DIR/
  chown -R $SFTP_USER_NAME:$SFTP_GROUP_NAME $SFTP_DIR/
  chmod 700 $SFTP_DIR/
}

# ENABLE USER
function enable_user()
{
  read -p "PLEASE PROVIDE THE USERNAME: " USER_NAME
  check_user $USER_NAME
  local RES=$?
  if [ $RES -eq 0 ];then
    if usermod -e "" $USER_NAME &>/dev/null;then
      echo "[+] USER [ $USER_NAME ] ENABLED"
    else
      echo "[!] PROBLEM WHILE ENABLING [ $USER_NAME ] USER"
    fi
  elif [ $RES -eq 1 ];then
    echo "[!] CAN NOT ENABLE [ $USER_NAME ] BECAUSE IT'S NOT CREATED BY THIS SCRIPT"
  elif [ $RES -eq 2 ];then
    echo "[!] PLEASE PROVIDE AN EXISTING USER"
  fi
}

#DISABLE GIVEN USER
function disable_user()
{
  read -p "PLEASE PROVIDE THE USERNAME: " USER_NAME
  check_user $USER_NAME
  local RES=$?
  if [ $RES -eq 0 ];then
    if usermod -e 1 $USER_NAME &>/dev/null;then
      echo "[+] USER [ $USER_NAME ] DISABLED"
    else
      echo "[!] PROBLEM WHILE DISABLING [ $USER_NAME ] USER"
    fi
  elif [ $RES -eq 1 ];then
    echo "[!] CAN NOT DISABLE [ $USER_NAME ] BECAUSE IT'S NOT CREATED BY THIS SCRIPT"
  elif [ $RES -eq 2 ];then
    echo "[!] PLEASE PROVIDE AN EXISTING USER"
  fi
}

#DELETE USER
function delete_user()
{
  while true;do
    read -p "[+] PLEASE PROVIDE THE USERNAME: " USER_NAME
    if [ -z $USER_NAME ];then
      echo "[!] USERNAME CAN NOT BE EMPTY"
    else
      break
    fi
  done
  check_user $USER_NAME
  local RES=$?
  if [ $RES -eq 0 ];then
    ask
    if [ $? -eq 0 ];then
      if ! deluser $USER_NAME;then
        echo "[!] FAILED TO REMOVE [ $USER_NAME ] USER"
        exit
      else
        echo "[+] USER [ $USER_NAME ] HAS BEEN REMOVED"
        sed -i "/.*$COMMENT.*$USER_NAME/d" $SSHD_CONFIG_USER
        echo "[!] WARNING: AFTER REMOVING THE USERNAME, YOUR DATA ARE ASSIGNED TO A NON-EXISTING USER [!]"
        echo "[!] IT'S HIGHLY RECOMMENDED TO FIX THE PERMISSION IMMEDIATELY [!]"
      fi
    fi
  elif [ $RES -eq 1 ];then
    echo "[!] CAN NOT DELETE [ $USER_NAME ] USER BECAUSE IT'S NOT CREATED BY THIS SCRIPT"
  elif [ $RES -eq 2 ];then
    echo "[!] PLEASE PROVIDE AN EXISTING USER"
  fi
}

#DELETE GROUP
function delete_group()
{
  while true;do
    read -p "[+] PLEASE PROVIDE THE GROUP NAME: " GROUP_NAME
    if [ -z $GROUP_NAME ];then
      echo "[!] GROUP NAME CAN NOT BE EMPTY"
    else
      break
    fi
  done
  check_group $GROUP_NAME
  local RES=$?
  if [ $RES -eq 0 ];then
    ask
    if [ $? -eq 0 ];then
      if ! delgroup $GROUP_NAME;then
        echo "[!] FAILED TO REMOVE THE [ $GROUP_NAME ] GROUP"
        exit
      else
        echo "[+] GROUP [ $GROUP_NAME ] HAS BEEN REMOVED REMOVED"
        sed -i "/.*$COMMENT.*$GROUP_NAME/d" $SSHD_CONFIG_GROUP
        echo "[!] WARNING: AFTER REMOVING THE GROUP, YOUR DATA ARE ASSIGNED TO A NON-EXISTING GROUP [!]"
        echo "[!] IT'S HIGHLY RECOMMENDED TO FIX THE PERMISSION IMMEDIATELY [!]"
      fi
    fi
  elif [ $RES -eq 1 ];then
    echo "[!] CAN NOT DELETE [ $GROUP_NAME ] GROUP BECAUSE IT'S NOT CREATED BY THIS SCRIPT"
  elif [ $RES -eq 2 ];then
    echo "[!] PLEASE PROVIDE AN EXISTING GROUP"
  fi
}


#CREATE GROUP
function add_group()
{
  while true;do
    read -p "PLEASE PROVIDE A GROUP NAME: " GROUP_NAME
    if [ -z $GROUP_NAME ];then
      echo "[!] GROUP NAME CAN NOT BE EMPTY"
    else
      break
    fi
  done
  check_group $GROUP_NAME
  local RES=$?
  if [ $RES -eq 0 ];then
    echo "[+] GROUP [ $GROUP_NAME ] ALREADY FOUND AND CREATED BY THIS SCRIPT, SKIPPING ..."
  elif [ $RES -eq 1 ];then
    echo "[!] GROUP [ $GROUP_NAME ] FOUND BUT NOT CREATED BY THIS SCRIPT"
    echo "[!] PLEASE USE ANOTHER GROUP NAME"
  elif [ $RES -eq 2 ];then
    echo "[+] WHAT IS THE ChrootDirectory FOR THIS GROUP"
    read -p "DEFAULT IS [ /home ] " CHROOT_DIR
    if [ -z $CHROOT_DIR ];then
      CHROOT_DIR="/home"
    fi
    if ! echo $CHROOT_DIR | grep -q '\%';then
      if ! echo "$CHROOT_DIR" | grep -Eq '^/.*';then
        echo "[!] ONLY FULL PATH IS ACCEPTED [!]"
      else
        if groupadd $GROUP_NAME &>/dev/null;then
          sed -i "/^${GROUP_NAME}:/s/$/:${COMMENT}/" /etc/group
          echo "[+] GROUP [ $GROUP_NAME ] CREATED"
          if [[ $CHROOT_DIR != "/home/" ]];then
            mkdir -p $CHROOT_DIR && chown root:root $CHROOT_DIR
            mkdir -p $CHROOT_DIR/$SFTP_USER_NAME
          fi
          sshd_config_group "$GROUP_NAME" "${CHROOT_DIR}"
        else
          echo "[!] FAILED TO CREATE THE [ $GROUP_NAME ] GROUP"
          exit
        fi
      fi
    else
      echo "[!] USING [ % ] IS NOT ALLOWED [!]"
      echo "[!] ABORTING [!]"
    fi
  fi
}

#ADD USER
function add_user()
{
  while true;do
    read -p "PLEASE PROVIDE A USER NAME: " SFTP_USER_NAME
    if [ -z $SFTP_USER_NAME ];then
      echo "[!] USER NAME CAN NOT BE EMPTY"
    else
      break
    fi
  done
  check_user $SFTP_USER_NAME
  local RES=$?
  if [ $RES -eq 0 ];then
    ORIGINAL_SFTP_DATA_DIR=$(cat $SSHD_CONFIG_USER | grep "$COMMENT" | grep "$SFTP_USER_NAME" | grep "ForceCommand" | awk '{print $4}' | sed -e "s/\#.*//g" |sed -e "s/^\///g")
    if [ -z $ORIGINAL_SFTP_DATA_DIR ];then
      echo "[!] USER [ $SFTP_USER_NAME ] IS CREATED BY THIS SCRIPT BUT MANUAL MODIFICATIONS HAPPENED"
      echo "[!] ABORTING [!]"
    else
      echo "[+] USER [ $SFTP_USER_NAME ] ALREADY FOUND WITH [ $ORIGINAL_SFTP_DATA_DIR ] DATA DIR AND CREATED BY THIS SCRIPT, SKIPPING ..."
    fi
  elif [ $RES -eq 1 ];then
    echo "[!] USER [ $SFTP_USER_NAME ] FOUND BUT NOT CREATED BY THIS SCRIPT"
    echo "[!] PLEASE USE ANOTHER USER NAME"
  elif [ $RES -eq 2 ];then
    #USER NOT FOUND, CREATE IT
    #ASK TO WHICH GROUP FIRST
    while true;do
      read -p "[+] TO WHICH GROUP YOU WANT TO ADD THE USER? " SFTP_GROUP_NAME
      if [ -z $SFTP_GROUP_NAME ];then
        echo "[!] GROUP NAME CAN NOT BE EMPTY"
      else
        break
      fi
    done
    check_group $SFTP_GROUP_NAME
    RES=$?
    if [ $RES -eq 0 ];then
      CHROOT_DIR=$(cat $SSHD_CONFIG_GROUP | grep "$COMMENT" | grep "$SFTP_GROUP_NAME" | grep ChrootDirectory | awk '{print $2}' | sed -e "s/\#.*//g" | sed -e "s/%u$//g")
      echo "[+] GROUP [ $SFTP_GROUP_NAME ] ALREADY FOUND WITH ChrootDirectory [ $CHROOT_DIR ] AND CREATED BY THIS SCRIPT, SKIPPING ..."
      SKIP_USER_CREATION=false
    elif [ $RES -eq 1 ];then
     echo "[!] GROUP [ $SFTP_GROUP_NAME ] FOUND BUT NOT CREATED BY THIS SCRIPT"
     echo "[!] PLEASE USE ANOTHER GROUP NAME"
     SKIP_USER_CREATION=true
    elif [ $RES -eq 2 ];then
      echo "[!] PLEASE ADD THE GROUP FIRST WITH THE OPTION [ 2 ]"
      SKIP_USER_CREATION=true
    fi
    if ! $SKIP_USER_CREATION;then
      echo "[+] PLEASE PROVIDE THE USER DATA DIR"
      read -p "DEFAULT IS [ data ] " SFTP_DATA_DIR
      if [ -z $SFTP_DATA_DIR ];then
        SFTP_DATA_DIR="data"
      fi
      if ! echo $SFTP_DATA_DIR | grep -q '\%';then
        if useradd -g $SFTP_GROUP_NAME -c "$COMMENT" -d /home/$SFTP_USER_NAME/ -m -s /sbin/nologin $SFTP_USER_NAME;then
          echo "[+] USER [ $SFTP_USER_NAME ] CREATED"
          if [[ "$CHROOT_DIR" != "/home/" ]];then
            mkdir -p $CHROOT_DIR/$SFTP_USER_NAME && chown root:root $CHROOT_DIR/$SFTP_USER_NAME
          else
            chown root:root /home/$SFTP_USER_NAME
            chmod 755 /home/$SFTP_USER_NAME
          fi
          set_permission "$SFTP_USER_NAME" "$SFTP_GROUP_NAME" "$CHROOT_DIR/$SFTP_USER_NAME/$SFTP_DATA_DIR"
          sshd_config_user "$SFTP_USER_NAME" "$SFTP_DATA_DIR"
          echo "[!] PLEASE DON'T FORGET TO ADD YOUR SSH PUBLIC KEY TO [ /home/$SFTP_USER_NAME/.ssh/authorized_keys ]"
        else
          echo "[!] FAILED TO CREATE THE USER [ $SFTP_USER_NAME ]"
          exit
        fi
      else
        echo "[!] USING [ % ] IS NOT ALLOWED"
        echo "[!] ABORTING AND REMOVING THE USER [!]"
      fi
    fi
  fi
}


#APPLY SSHD MODIFICATIONS
function apply_sshd_configs()
{
  local CONFIG=$1
  local MESSAGE=$2
  systemctl restart sshd
  sleep 2
  if [[ $(systemctl is-active sshd) != "active" ]];then
    echo "[!] SSH CONFIG FAILED AFTER ADDING THE $MESSAGE, RESETING SCRIPT MODIFICATION"
    touch $CONFIG
    systemctl restart sshd
    if [[ $(systemctl is-active sshd) == "active" ]];then
      echo "[+] SSHD CONFIG FIXED"
    else
      echo "[!] THE SCRIPT FAILED TO RECTIFY THE SSHD CONFIG"
      echo "[!] PLEASE FIX THE CONFIGS BEFORE CLOSING THE ROOT SHELL !"
      exit
    fi
  else
    echo "[+] SSHD CONFIG APPLIED"
  fi
}

#CONFIGURE SSHD USER JAIL
function sshd_config_user()
{
  SFTP_USER_NAME=$1
  SFTP_USER_DATA=$2
  [ ! -d `dirname $SSHD_CONFIG_USER` ] && mkdir -p `dirname $SSHD_CONFIG_USER`
  [ ! -f $SSHD_CONFIG_USER ] && touch $SSHD_CONFIG_USER
  if ! cat $SSHD_CONFIG_USER | grep -q "Match User $SFTP_USER_NAME # [ $COMMENT ] # $SFTP_USER_NAME";then
    echo "[+] ADDED THE FOLLOWING TO THE [ $SSHD_CONFIG_USER ] CONFIG FILE"
    echo "---------------------------"
    echo "Match User $SFTP_USER_NAME # [ $COMMENT ] # $SFTP_USER_NAME" | tee -a $SSHD_CONFIG_USER
    echo "ForceCommand internal-sftp -d $SFTP_USER_DATA # [ $COMMENT ] # $SFTP_USER_NAME" | tee -a $SSHD_CONFIG_USER
    echo "AuthorizedKeysFile /home/%u/.ssh/authorized_keys # [ $COMMENT ] # $SFTP_USER_NAME" | tee -a $SSHD_CONFIG_USER
    echo "---------------------------"
  fi
  apply_sshd_configs "$SSHD_CONFIG_USER" "SFTP USER [ $SFTP_USER_NAME ] CONFIG"
  chmod 700 $SSHD_CONFIG_USER
}

#CONFIGURE SSHD GROUP JAIL
function sshd_config_group()
{
  local SFTP_GROUP_NAME=$1
  local CHROOT_DIR=$2
  [ ! -d `dirname $SSHD_CONFIG_GROUP` ] && mkdir -p `dirname $SSHD_CONFIG_GROUP`
  [ ! -f $SSHD_CONFIG_GROUP ] && touch $SSHD_CONFIG_GROUP
  if ! cat $SSHD_CONFIG_GROUP | grep -q "Match Group $SFTP_GROUP_NAME # [ $COMMENT ] # $SFTP_GROUP_NAME";then
    echo "[+] ADDED THE FOLLOWING TO THE [ $SSHD_CONFIG_GROUP ] CONFIG"
    echo "---------------------------"
    echo "Match Group $SFTP_GROUP_NAME # [ $COMMENT ] # $SFTP_GROUP_NAME" | tee -a $SSHD_CONFIG_GROUP
    echo "ChrootDirectory ${CHROOT_DIR}/%u # [ $COMMENT ] # $SFTP_GROUP_NAME" | tee -a $SSHD_CONFIG_GROUP
    echo "PubkeyAuthentication yes # [ $COMMENT ] # $SFTP_GROUP_NAME" | tee -a $SSHD_CONFIG_GROUP
    echo "ChallengeResponseAuthentication no # [ $COMMENT ] # $SFTP_GROUP_NAME" | tee -a $SSHD_CONFIG_GROUP
    echo "PasswordAuthentication no # [ $COMMENT ] # $SFTP_GROUP_NAME" | tee -a $SSHD_CONFIG_GROUP
    echo "AllowTcpForwarding no # [ $COMMENT ] # $SFTP_GROUP_NAME" | tee -a $SSHD_CONFIG_GROUP
    echo "PermitTunnel no # [ $COMMENT ] # $SFTP_GROUP_NAME" | tee -a $SSHD_CONFIG_GROUP
    echo "X11Forwarding no # [ $COMMENT ] # $SFTP_GROUP_NAME" | tee -a $SSHD_CONFIG_GROUP
    echo "PermitTTY no # [ $COMMENT ] # $SFTP_GROUP_NAME" | tee -a $SSHD_CONFIG_GROUP
    echo "---------------------------"
  fi
  apply_sshd_configs "$SSHD_CONFIG_GROUP" "SFTP GROUP [ $SFTP_GROUP_NAME ] CONFIG"
  chmod 700 $SSHD_CONFIG_GROUP
}

#CONFIGURE GLOBAL SSHD
function sshd_config()
{
  if [ ! -f ${SSHD_CONFIG}.backup ];then
    if cp $SSHD_CONFIG ${SSHD_CONFIG}.backup;then
      echo "[+] ${SSHD_CONFIG}.backup BACKUP CREATED"
    else
      echo "[!] FAILED TO BACKUP $SSHD_CONFIG"
      exit
    fi
  fi
  echo "[+] DISABLING OLD SFTP CONFIG"
  sed -i "/^$OLD_CONFIG/ s|^|#|" $SSHD_CONFIG
  if ! grep -q "^$NEW_CONFIG" $SSHD_CONFIG;then
    verify_entry $SSHD_CONFIG "Subsystem       sftp    internal-sftp"
    echo "[+] RESTARTING SSH SERVER"
    systemctl restart sshd
    sleep 2
    if [[ $(systemctl is-active sshd) != "active" ]];then
      echo "[!] SSH CONFIG FAILED, RESTORING FROM ${SSHD_CONFIG}.backup"
      cp ${SSHD_CONFIG}.backup ${SSHD_CONFIG}
    fi
  fi
}


#MAIN
#REQUIRED BINARIES
BINARIES="which getent cat sshd grep tee"
for BINARY in $BINARIES;do
  if ! which $BINARY &>/dev/null;then
    echo "[!] MISSING REQUIRED BINARY: $BINARY"
    exit
  fi
done

echo "[!] PLEASE MAKE SURE TO OPEN ANOTHER ROOT SHELL FOR SAFETY REASONS [!]"
read -p "PRESS ENTER TO CONTINUE ..."

#USED TO MAKE SURE THE SCRIPT CAN ONLY MANAGE USERS/GROUPS CREATED BY IT ONLY
COMMENT="CREATED BY THE AUTOMATED SFTP JAIL SCRIPT"

SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_USER="$SSHD_CONFIG_DIR/sftp-jail-user.conf"
SSHD_CONFIG_GROUP="$SSHD_CONFIG_DIR/sftp-jail-group.conf"
OLD_CONFIG="Subsystem.*sftp.*\/usr\/lib\/openssh\/sftp-server"
NEW_CONFIG="Subsystem.*sftp.*internal-sftp"

if ! grep -qE "^$NEW_CONFIG" $SSHD_CONFIG;then
  sshd_config
fi

[[ ! -d $SSHD_CONFIG_DIR ]] && mkdir -p $SSHD_CONFIG_DIR
[[ ! -f $SSHD_CONFIG_USER ]] && touch $SSHD_CONFIG_USER
[[ ! -f $SSHD_CONFIG_GROUP ]] && touch $SSHD_CONFIG_GROUP

SKIP_USER_CREATION=false

while true; do
  display_menu
  read -p "ENTER YOUR CHOICE (1-6): " CHOICE
  case $CHOICE in
    1) add_user ;;
    2) add_group;;
    3) delete_user ;;
    4) delete_group ;;
    5) enable_user ;;
    6) disable_user ;;
    0) echo "EXITING THE SCRIPT !"; exit 0 ;;
    *) echo "INVALID CHOICE." ;;
  esac

  echo "PRESS ENTER TO CONTINUE ..."
  read
done
