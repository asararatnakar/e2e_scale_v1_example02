#!/bin/bash
START_TIME=$(date +%s)

##### GLOBALS ######
CHANNEL_NAME="$1"
CHANNELS="$2"
CHAINCODES="$3"
ENDORSERS="$4"

##### SET DEFAULT VALUES #####
: ${CHANNEL_NAME:="mychannel"}
: ${CHANNELS:="1"}
: ${CHAINCODES:="1"}
: ${ENDORSERS:="4"}
: ${TIMEOUT:="90"}
COUNTER=0
MAX_RETRY=5
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/orderer/localMspConfig/cacerts/ordererOrg0.pem
#ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/e2e/crypto/orderer/localMspConfig/cacerts/ordererOrg0.pem

# find address of orderer and peers in your network
ORDERER_IP=orderer0
#ORDERER_IP=`perl -e 'use Socket; $a = inet_ntoa(inet_aton("orderer0")); print "$a\n";'`
#PEER0_IP=`perl -e 'use Socket; $a = inet_ntoa(inet_aton("peer0")); print "$a\n";'`
#PEER1_IP=`perl -e 'use Socket; $a = inet_ntoa(inet_aton("peer1")); print "$a\n";'`
#PEER2_IP=`perl -e 'use Socket; $a = inet_ntoa(inet_aton("peer2")); print "$a\n";'`
#PEER3_IP=`perl -e 'use Socket; $a = inet_ntoa(inet_aton("peer3")); print "$a\n";'`

#echo "-----------------------------------------"
#echo "Orderer IP $ORDERER_IP"
#echo "PEER0 IP $PEER0_IP"
#echo "PEER1 IP $PEER1_IP"
#echo "PEER2 IP $PEER2_IP"
#echo "PEER3 IP $PEER3_IP"


echo "Channel name prefix: $CHANNEL_NAME"
echo "Total channels: $CHANNELS"
echo "Total Chaincodes: $CHAINCODES"
echo "Total Endorsers: $ENDORSERS"
echo "-----------------------------------------"

verifyResult () {
	if [ $1 -ne 0 ] ; then
		echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
                echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
		echo
		echo "Total execution time $(($(date +%s)-START_TIME)) secs"
   		exit 1
	fi
}

setGlobals () {
	CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peer/peer$1/localMspConfig
	CORE_PEER_ADDRESS=peer$1:7051
	if [ $1 -eq 0 -o $1 -eq 1 ] ; then
		CORE_PEER_LOCALMSPID="Org0MSP"
		CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peer/peer$1/localMspConfig/cacerts/peerOrg0.pem
	else
		CORE_PEER_LOCALMSPID="Org1MSP"
		CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peer/peer$1/localMspConfig/cacerts/peerOrg1.pem
	fi
	# env |grep CORE
}

createChannel() {
	CHANNEL_NUM=$1
	CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/orderer/localMspConfig
	CORE_PEER_LOCALMSPID="OrdererMSP"
	echo "===================== Creating Channel \"$CHANNEL_NAME$CHANNEL_NUM\" using $ORDERER_IP:7050"
	echo "===================== CORE_PEER_TLS_ENABLED=$CORE_PEER_TLS_ENABLED"
	echo "===================== cafile=$ORDERER_CA"
	echo "CORE_PEER_MSPCONFIGPATH contents : "
        if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
	        peer channel create -o $ORDERER_IP:7050 -c ${CHANNEL_NAME}${CHANNEL_NUM} -f crypto/orderer/channel${CHANNEL_NUM}.tx >&log.txt
        else
	        peer channel create -o $ORDERER_IP:7050 -c $CHANNEL_NAME$CHANNEL_NUM -f crypto/orderer/channel$CHANNEL_NUM.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
        fi

	res=$?
	cat log.txt
	verifyResult $res "Channel creation with name \"$CHANNEL_NAME$CHANNEL_NUM\" has failed"
	echo "===================== Channel \"$CHANNEL_NAME$CHANNEL_NUM\" is created successfully ===================== "
	echo
}

## Sometimes Join takes time hence RETRY atleast for 5 times
joinWithRetry () {
	for (( i=0; $i<$CHANNELS; i++))
	do
		peer channel join -b $CHANNEL_NAME$i.block  >&log.txt
		res=$?
		cat log.txt
		if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
			COUNTER=` expr $COUNTER + 1`
			echo "PEER$1 failed to join the channel 'mychannel$i', Retry after 2 seconds"
			sleep 2
			joinWithRetry $1
		else
			COUNTER=0
		fi
        	verifyResult $res "After $MAX_RETRY attempts, PEER$ch has failed to Join the Channel"
		echo "===================== PEER$1 joined on the channel \"$CHANNEL_NAME$i\" ===================== "
		sleep 2
	done
}

joinChannel () {
	PEER=$1
	setGlobals $PEER
	joinWithRetry $PEER
	echo "===================== PEER$PEER joined on $CHANNELS channel(s) ===================== "
	sleep 2
	echo
}

installChaincode () {
	for (( i=0; $i<$ENDORSERS; i++))
	do
		for (( ch=0; $ch<$CHAINCODES; ch++))
		do
			PEER=$i
			setGlobals $PEER
			peer chaincode install -n mycc$ch -v 1.0 -p github.com/hyperledger/fabric/examples/chaincode/go/chaincode_example02 >&log.txt
			res=$?
			cat log.txt
		        verifyResult $res "Chaincode 'mycc$ch' installation on remote peer PEER$PEER has Failed"
			echo "+++===================== Chaincode 'mycc$ch' is installed on remote peer PEER$PEER `date` "
			echo
		done
	done
}

instantiateChaincode () {
	PEER=$1
	setGlobals $PEER
	for (( i=0; $i<$CHANNELS; i++))
	do
		for (( ch=0; $ch<$CHAINCODES; ch++))
		do
			#PEER=` expr $ch \/ 4`
			#setGlobals $PEER
                        if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
			        peer chaincode instantiate -o $ORDERER_IP:7050 -C $CHANNEL_NAME$i -n mycc$ch -v 1.0 -p github.com/hyperledger/fabric/examples/chaincode/go/chaincode_example02 -c '{"Args":["init","a","1000","b","2000"]}' -P "OR	('Org0MSP.member','Org1MSP.member')" >&log.txt
                        else
			        peer chaincode instantiate -o $ORDERER_IP:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME$i -n mycc$ch -v 1.0 -p github.com/hyperledger/fabric/examples/chaincode/go/chaincode_example02 -c '{"Args":["init","a","1000","b","2000"]}' -P "OR	('Org0MSP.member','Org1MSP.member')" >&log.txt
                        fi
			res=$?
			cat log.txt
			verifyResult $res "Chaincode 'mycc$ch' instantiation on PEER$PEER on channel '$CHANNEL_NAME$i' failed"
			echo "+++===================== Chaincode 'mycc$ch' Instantiation on PEER$PEER on channel '$CHANNEL_NAME$i' is successful `date` "
			echo
		done
	done
}

chaincodeQuery () {
  local channel_num=$1
  local chain_num=$2
  local peer=$3
  local res=$4
  echo "===================== Querying on PEER$peer on $CHANNEL_NAME$channel_num/mycc$chain_num... `date`"
  local rc=1
  local starttime=$(date +%s)

  # continue to poll
  # we either get a successful response, or reach TIMEOUT
  while test "$(($(date +%s)-starttime))" -lt "$TIMEOUT" -a $rc -ne 0
  do
     echo "Query on PEER$peer ... $(($(date +%s)-starttime)) secs"
     peer chaincode query -C $CHANNEL_NAME$channel_num -n mycc$chain_num -c '{"Args":["query","a"]}' >&log.txt
     test $? -eq 0 && VALUE=$(cat log.txt | awk '/Query Result/ {print $NF}')
     test "$VALUE" = "$res" && let rc=0
     if test $VALUE -ne $res ; then
         sleep 1
     fi
  done
  echo
  cat log.txt
  if test $rc -eq 0 ; then
	echo "+++===== Query result on PEER$peer on $CHANNEL_NAME$channel_num/mycc$chain_num is successful : VALUE=$VALUE `date`"
	echo
  else
	echo "+++!!!!!!!!!!!!!! Query result on PEER$peer on $CHANNEL_NAME$channel_num/mycc$chain_num FAILED! VALUE=$VALUE != expected $res `date` !!!!!"
        echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
	echo
	echo "Total execution time for single query: $(($(date +%s)-START_TIME)) secs"
	#echo "SKIPPING Exit, for debugging, to check other values too!!!!!"
	exit 1
  fi
}

chaincodeInvoke () {
        local channel_num=$1
	local chain_num=$2
        local peer=$3
        if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
	        peer chaincode invoke -o $ORDERER_IP:7050 -C $CHANNEL_NAME$channel_num -n mycc$chain_num -c '{"Args":["invoke","a","b","10"]}' >&log.txt
        else
	        peer chaincode invoke -o $ORDERER_IP:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME$channel_num -n mycc$chain_num -c '{"Args":["invoke","a","b","10"]}' >&log.txt
        fi
	res=$?
	cat log.txt
	verifyResult $res "Invoke execution on PEER$peer failed "
	echo "+++===================== Invoke transaction on PEER$peer on $CHANNEL_NAME$channel_num/mycc$chain_num is successful `date`"
	echo
}

CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/orderer/localMspConfig
CORE_PEER_LOCALMSPID="OrdererMSP"
## Create channel
for (( ch=0; $ch<$CHANNELS; ch++))
do
	createChannel $ch
done

## Join all the peers to all the channels
for (( peer=0; $peer<$ENDORSERS; peer++))
do
	echo "====================== Joining PEER$peer on all channels ==============="
	joinChannel $peer
done

## Install chaincode on Peer0/Org0 and Peer2/Org1
echo "Installing chaincode on all Peers ..."
installChaincode

#Instantiate chaincode on Peer2/Org1
echo "Instantiating all chaincodes on all channels, using PEER1 ..."
instantiateChaincode 1

echo "sleep 10"
sleep 10

BATCHSIZE=100       # CONFIGTX_ORDERER_BATCHSIZE_MAXMESSAGECOUNT
BATCHTIMEOUT=10
TXSIZE=10           # this is how much is subtracted from A, during the Invoke
TXS_FIRST_INVOKE=1
AVAL_DIFF_FIRST_INVOKE=`expr $TXS_FIRST_INVOKE \* $TXSIZE`
AVAL_INIT=1000
AVAL_FIRST_INVOKE=`expr $AVAL_INIT - $AVAL_DIFF_FIRST_INVOKE`

# number of batches = number of transactions_per_peer * num_peers / batchsize
TXS_PER_PEER=4
TX_COUNT_PER_CHAN=$(( ${TXS_PER_PEER} * ${ENDORSERS} * ${CHAINCODES} ))
echo "TX_COUNT_PER_CHAN=$TX_COUNT_PER_CHAN, sum of all TX on all chaincodes on all peers on each channel"
TX_BATCHES=$(( ${TX_COUNT_PER_CHAN} / ${BATCHSIZE} ))
if [ $(( $TX_COUNT_PER_CHAN % $BATCHSIZE )) -ne 0 ]
then
  TX_BATCHES=$(( $TX_BATCHES + 1 ))
fi
AVAL_DIFF_VALID_TX=`expr $TX_BATCHES \* $TXSIZE`
AVAL_TARGET=`expr $AVAL_FIRST_INVOKE - $AVAL_DIFF_VALID_TX`
echo "TX_BATCHES=$TX_BATCHES per channel, plus the initial ones for each chaincode on each channel, sent in individual blocks"
echo "AVAL_TARGET=$AVAL_TARGET"
### this should work for one chaincode, but when using multiple chaincodes:
### the TX on one chaincode could straddle batches and potentially final AVAL be affected
### And even if diff batches, some TX proposals could be en route before first batch is written to ledger.
### This is not easy to predict exactly which or how many TXs will be valid or rejected!!!


# Query/Invoke/Query on all chaincodes on all channels on all peers
#echo "send Invokes/Queries on all channels ..."
#for (( ch=0; $ch<$CHANNELS; ch++))
#do
#	for (( chain=0; $chain<$CHAINCODES; chain++))
#	do
#                AVAL=$AVAL_INIT
#		for (( peer_number=0; $peer_number<$ENDORSERS; peer_number++))
#		do
#			setGlobals "$peer_number"
#			chaincodeQuery $ch $chain $peer_number "$AVAL"
#			chaincodeInvoke $ch $chain $peer_number
#			AVAL=` expr $AVAL - 10 `
#			chaincodeQuery $ch $chain $peer_number "$AVAL"
#		done
#	done
#done


# Query on all chaincodes on all channels on all peers
QUERIES_START_TIME=$(date +%s)
echo "FIRST Send Queries on all channels / chaincodes / peers ..."
echo "AVAL TARGET BEFORE any invokes : $AVAL_INIT"
for (( ch=0; $ch<$CHANNELS; ch++))
do
	for (( chain=0; $chain<$CHAINCODES; chain++))
	do
		for (( peer_number=0; $peer_number<$ENDORSERS; peer_number++))
		do
			setGlobals "$peer_number"
			chaincodeQuery $ch $chain $peer_number "$AVAL_INIT"
		done
	done
done
echo "QUERIES execution time $(($(date +%s)-QUERIES_START_TIME)) secs"


#Invoke once all chaincodes on all channels on all peers
INVOKES_START_TIME=$(date +%s)
echo "First, send single Invoke on all peers on all chaincodes on all channels, to initialize and sync each peer chaincode:"
for (( ch=0; $ch<$CHANNELS; ch++))
do
        INVOKES_TX_PEER_START_TIME=$(date +%s)
	for (( chain=0; $chain<$CHAINCODES; chain++))
	do
		for (( peer_number=0; $peer_number<$ENDORSERS; peer_number++ ))
                do
			        setGlobals "$peer_number"
			        chaincodeInvoke $ch $chain $peer_number
		done
	done
        echo "INITIAL INVOKES on channel$ch, once on all $ENDORSERS peers for all $CHAINCODES chaincodes; execution time $(($(date +%s)-INVOKES_TX_PEER_START_TIME)) secs"
        echo " "
        #sleep $BATCHTIMEOUT
done
echo "FIRST INVOKES done throughout network; execution time $(($(date +%s)-INVOKES_START_TIME)) secs"
echo ""
sleep $BATCHTIMEOUT



# Query on all chaincodes on all channels on all peers
QUERIES_START_TIME=$(date +%s)
echo "Send Queries on all channels / chaincodes / peers ..."
echo "AVAL TARGET after single invoke = $AVAL_FIRST_INVOKE"
for (( ch=0; $ch<$CHANNELS; ch++))
do
	for (( chain=0; $chain<$CHAINCODES; chain++))
	do
		for (( peer_number=0; $peer_number<$ENDORSERS; peer_number++))
		do
			setGlobals "$peer_number"
			chaincodeQuery $ch $chain $peer_number "$AVAL_FIRST_INVOKE"
		done
	done
done
echo "QUERIES execution time $(($(date +%s)-QUERIES_START_TIME)) secs"



#Invoke on all chaincodes on all channels on all peers
# Note: with example02 and batchtimeout=10, only one invoke to one peer out of the group is expected to be successful
INVOKES_START_TIME=$(date +%s)
echo "send Invokes on all channels ... $TX_COUNT_PER_CHAN Invoke TXs per channel, divided among on each peer and chaincode"
for (( ch=0; $ch<$CHANNELS; ch++))
do
        INVOKES_TX_PEER_CC_START_TIME=$(date +%s)
	for (( chain=0; $chain<$CHAINCODES; chain++))
	do
		for (( peer_number=0; $peer_number<${ENDORSERS}; peer_number++))
                do
		        for (( numTx=0; $numTx<${TXS_PER_PEER}; numTx++))
		        do
			        setGlobals "$peer_number"
			        chaincodeInvoke $ch $chain $peer_number
		        done
		done
	done
        echo "ALL INVOKES on channel$ch: $TXS_PER_PEER on all $ENDORSERS peers on all $CHAINCODES chaincodes; execution time $(($(date +%s)-INVOKES_TX_PEER_CC_START_TIME)) secs"
        echo ""
        #sleep $BATCHTIMEOUT
done

SUM_TXS=$(( $ch * $CHAINCODES * $ENDORSERS * $TXS_PER_PEER ))
echo "Finished all $SUM_TXS INVOKEs. execution time $(($(date +%s)-INVOKES_START_TIME)) secs"
echo ""
sleep $BATCHTIMEOUT


# Query on all chaincodes on all channels on all peers
# but with batchtimeout=10, only one invoke to one peer out of the group should be successful
QUERIES_START_TIME=$(date +%s)
echo "Send Queries on all channels / chaincodes / peers ..."
echo "AVAL_TARGET=$AVAL_TARGET"
for (( ch=0; $ch<$CHANNELS; ch++))
do
	for (( chain=0; $chain<$CHAINCODES; chain++))
	do
		for (( peer_number=0; $peer_number<$ENDORSERS; peer_number++))
		do
			setGlobals "$peer_number"
			chaincodeQuery $ch $chain $peer_number "$AVAL_TARGET"
		done
	done
done
echo "QUERIES execution time $(($(date +%s)-QUERIES_START_TIME)) secs"

echo
echo "===================== All GOOD, End-2-End execution completed ===================== "
echo
echo "Total execution time $(($(date +%s)-START_TIME)) secs"
exit 0
