#!/bin/bash
#ryanyluo

function usage(){

    echo "IpaResignFull inject dylib and resign the ipa."
    echo "-p : Provision profile"
    echo "-i : Input ipa"
    echo "-d : Injected dylib (Optional)"
    #echo "-c : Certification name"

}

while getopts ':p:i:c:' opt
do
    case $opt in
         p) MOBILE_PROVISION=$OPTARG
            ;;
    #     c) CERTIFICATION=$OPTARG
    #        ;;
         i) SRC_IPA=$OPTARG
            ;;
         d) DYLIB_FILE=$OPTARG
            ;;
        \?)
            echo "Invalid option -$OPTARG."
            exit 1
            ;;
    esac
done

#check arguments
if [[ -z "$MOBILE_PROVISION" || -z "$SRC_IPA" ]]; then
    echo "Wrong arguments!"
    usage
    exit 1
fi

function checkInt()
{
    if [[ $# -ne 1 ]]; then
        return -1
    fi

    temp=$(echo $1 | grep '^\(\(0\)\|\(-\{0,1\}[1-9][0-9]*\)\)$')
    if [[ -z $temp ]]; then
        return 0
    else
        return 1
    fi
}

#search certificates
INDEX=0
######################################################################
#while read line; do
#    ALL_CER[$INDEX]="$line"
#    (( INDEX=INDEX+1 ))
#
#    TEMP_PEM=t.pem
#    FIND_RESULT=$(security find-certificate -c "$line" -p > $TEMP_PEM 2>&1)
#
#    if [[ -z $FIND_RESULT ]]; then
#        VERY_RESULT_ARR=($(security verify-cert -c $TEMP_PEM 2>&1))
#        ARR_LEN=${#VERY_RESULT_ARR[*]}
#        (( LAST_IDX=ARR_LEN-1 ))
#        ALL_VERIFY_RESULT[$INDEX]=${VERY_RESULT_ARR[$LAST_IDX]}
#        #echo ${ALL_VERIFY_RESULT[INDEX]}
#        rm $TEMP_PEM
#    fi
#done < <(security find-certificate -a | sed -n 's/\"alis\"<blob>=\"\(.*\)\"/\1/p')
######################################################################

FLAG=0
while read line; do
    if [[ $FLAG -eq 0 ]]; then
        ALL_CER[$INDEX]="$line"
        FLAG=1
    else
        ALL_VERIFY_RESULT[$INDEX]="$line"
        FLAG=0
        (( INDEX=INDEX+1 ))
    fi
done < <(security find-identity -p codesigning 2>&1 | awk -F '"' '
BEGIN { flag=0 }
/Matching identities/ { flag=1 }
/Valid identities/ { flag=0 }
/\d*\)/ {
            if (flag==1){ 
                print $2;
                vl=length($3)
                print substr($3, 3, vl-3);
            }
        }
')

if [[ -z $ALL_CER ]]; then
    echo 'No Valid Certificate in keychain!'
    exit 1
fi

# user select devices 
CER_NUM=${#ALL_CER[*]}
echo 'Existing Certificate:'
for (( i=0; i<$CER_NUM; i++ )); do
    echo "[$i] \"${ALL_CER[i]}\", verify result: ${ALL_VERIFY_RESULT[i]}"
done
echo -n 'Please select a certificate(0~'$[CER_NUM-1]'):'
read idx

$(checkInt $idx)
while [[ $? -ne 1 ||  $idx -ge $CER_NUM || $idx -lt 0 ]]; do
    echo -n 'Error input. Please select a certificate(0~'$[CER_NUM-1]'):'
    read idx
    if [[ -z idx ]] ; then
        exit 1
    fi
    $(checkInt $idx)
done
SELECT_CER=${ALL_CER[idx]}

#MATCHED_CERTIFICATE=$(security find-certificate -a -c "$CERTIFICATION" | grep class | wc -l)   
#if [[ $MATCHED_CERTIFICATE -eq 0 ]]; then
#    echo "\"$CERTIFICATION\" is not found in the keychain! Operatioin Not Finished! "
#    exit 1
#fi
#
#if [[ $MATCHED_CERTIFICATE -gt 1 ]]; then
#    echo "Multiple \"$CERTIFICATION\" are found in the keychain! Operatioin Not Finished! "
#    exit 1
#fi

#inject dylib
echo "Injecting dylib..."


DST_IPA="$SRC_IPA-resigned.ipa"
echo 
echo "Source IPA: $SRC_IPA"
echo "Provision Profile: $MOBILE_PROVISION"
echo "Certificate: $SELECT_CER"
echo "Dylib: $DYLIB_FILE"
echo "Calling IpaResign to resign ipa, the resigned ipa will be ${DST_IPA}~"
echo 

#-----------------------------------------------
# Start to resign the ipa
#-----------------------------------------------
unzip -q $SRC_IPA

#删除无关文件
if  test -f "bppinfo"; then
	rm "bppinfo"
fi

if  test -f "iTunesArtwork"; then
	rm "iTunesArtwork"
fi

if  test -d "META-INF"; then
	rm -rf "META-INF"
fi

# 重签名之后的ipa文件
if  test -f $DST_IPA; then
	rm $DST_IPA
fi

# remove the signature
rm -rf Payload/*.app/_CodeSignature Payload/*.app/CodeResources

# replace the provision
cp "$MOBILE_PROVISION" Payload/*.app/embedded.mobileprovision

#create entitlements
/usr/libexec/PlistBuddy -x -c "print :Entitlements " /dev/stdin <<< $(security cms -D -i Payload/*.app/embedded.mobileprovision) > entitlements.plist
/usr/libexec/PlistBuddy -c 'Set :get-task-allow true' entitlements.plist

# sign all Frameworks and app with the new certificate
DIR=`ls Payload/`
EXE_FILE_NAME=`/usr/libexec/PlistBuddy -c "print :CFBundleExecutable" Payload/*/Info.plist`
EXE_FILE_FULL_PATH="Payload/"$DIR"/"$EXE_FILE_NAME
RULE_FILE="Payload/*.app/ResourceRules.plist"
if  test -f $RULE_FILE; then
    echo "old rule"

    # 重签Framework
    if  test -d Payload/*.app/Frameworks; then
        for file in Payload/*.app/Frameworks/*
        do
            /usr/bin/codesign -f -s "$SELECT_CER" --resource-rules   Payload/*.app/ResourceRules.plist --entitlements entitlements.plist Payload/*.app/Frameworks/${file##*/}
        done 
    fi

    # 重签并注入dylib
    if [[ -n "$DYLIB_FILE" ]]; then
        /usr/bincodesign -f -s "$SELECT_CER" --force --verbose=4 "$DYLIB_FILE"
        cp -f "$DYLIB_FILE" Payload/*.app/
        echo "Injecting dylib into the executable file..."
        ./yololib "$EXE_FILE_FULL_PATH" $DYLIB_FILE
    fi

    /usr/bin/codesign -f -s "$SELECT_CER" --resource-rules   Payload/*.app/ResourceRules.plist --entitlements entitlements.plist Payload/*.app
else
    echo "new rule"
    
    # 重签Framework
    if  test -d Payload/*.app/Frameworks; then
        for file in Payload/*.app/Frameworks/*
        do
            /usr/bin/codesign -f -s "$SELECT_CER" --no-strict --entitlements entitlements.plist Payload/*.app/Frameworks/${file##*/}
        done 
    fi

    # 重签并注入dylib
    if [[ -n "$DYLIB_FILE" ]]; then
        /usr/bincodesign -f -s "$SELECT_CER" --force --verbose=4 "$DYLIB_FILE"
        cp -f "$DYLIB_FILE" Payload/*.app/
        echo "Injecting dylib into the executable file..."
        ./yololib "$EXE_FILE_FULL_PATH" $DYLIB_FILE
    fi

    /usr/bin/codesign -f -s "$SELECT_CER" --no-strict --entitlements entitlements.plist Payload/*.app
fi

#可执行文件增加执行权限
chmod a+x $EXE_FILE_FULL_PATH

# zip it back up
zip -qr "$DST_IPA" Payload

# 提示检查
echo 
echo "Resigned ipa's codesign: "
codesign -vv -d Payload/*.app
echo 
echo "Please Checkc mannually."

#clear temp file
rm entitlements.plist
rm -rf Payload

