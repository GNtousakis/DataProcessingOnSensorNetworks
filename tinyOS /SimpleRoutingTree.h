#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H


enum{
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=3,
	MAX_QUEUE_SIZE=3,
	AVG_QUEUE_SIZE=3,
	AM_SIMPLEROUTINGTREEMSG=22,
	AM_ROUTINGMSG=22,
	AM_NOTIFYPARENTMSG=12,
	TIMER_FAST_PERIOD=800,	//ROOTING
	TIMER_NEW_INFO= 60000,
};


/*uint16_t AM_ROUTINGMSG=AM_SIMPLEROUTINGTREEMSG;
uint16_t AM_NOTIFYPARENTMSG=AM_SIMPLEROUTINGTREEMSG;
*/


typedef nx_struct RoutingMsg
{
	nx_uint16_t senderID;
	nx_uint8_t depth;
	nx_uint8_t choicenumb; // 8 bitos arithmos o opoios analoga me tin timi tou mas dinei tis sinartiseis pou tha ektelestoun
} RoutingMsg;


typedef nx_struct NotifyParentMsg
{
	nx_uint8_t max;
	nx_uint16_t sum;
	nx_uint8_t count;

} NotifyParentMsg;

typedef nx_struct VeryVeryBigInfo
{
	nx_uint16_t data;
	nx_uint32_t data2;
	nx_uint8_t data3;

} VeryVeryBigInfo;

typedef nx_struct VeryVeryVeryBigInfo
{
	nx_uint16_t data;
	nx_uint32_t data2;
	nx_uint8_t data3;
	nx_uint8_t data4;

} VeryVeryVeryBigInfo;

typedef nx_struct VeryBigInfo
{
	nx_uint16_t data4;
	nx_uint8_t data5;
	nx_uint8_t data6;

} VeryBigInfo;


typedef nx_struct BigInfo
{
	nx_uint16_t data7;// px metrisi gia SUM 
	nx_uint8_t data8;//px metrisi gia COUNT

} BigInfo;

typedef nx_struct BigInfoSum
{
	nx_uint16_t data9;

} BigInfoSum;

typedef nx_struct SmallInfo
{
	nx_uint8_t data10;
} SmallInfo;

typedef nx_struct TwoSmallInfo	
{
	nx_uint8_t data11;
	nx_uint8_t data12;
} TwoSmallInfo;



typedef nx_struct StoredInfo
{
	nx_uint8_t number_child;
	message_t ab;
	nx_uint8_t max; //to maximum dedomeno 
	nx_uint16_t sum; // to athrisma
	nx_uint8_t count; // to plithos ton komvwn
	nx_uint8_t min; // to elaxisto 
} InfoTable;

#endif
