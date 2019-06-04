#include "SimpleRoutingTree.h"

configuration SRTreeAppC @safe() { }
implementation{
	components SRTreeC;

	components MainC,ActiveMessageC,RandomC;

	components new TimerMilliC() as RoutingMsgTimerC;
	components new TimerMilliC() as NeaMetrisiC;
	components new TimerMilliC() as NotifyParentTimerC;
	
	//tixaiotites
	components new TimerMilliC() as SendRootingTimerC;
	components new TimerMilliC() as SendParentTimerC;



	components new AMSenderC(AM_ROUTINGMSG) as RoutingSenderC;
	components new AMReceiverC(AM_ROUTINGMSG) as RoutingReceiverC;
	components new AMSenderC(AM_NOTIFYPARENTMSG) as NotifySenderC;
	components new AMReceiverC(AM_NOTIFYPARENTMSG) as NotifyReceiverC;

	components new PacketQueueC(MAX_QUEUE_SIZE) as MaxChildrenC;
	components new PacketQueueC(AVG_QUEUE_SIZE) as AvgChildrenC;

	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;
	components new PacketQueueC(SENDER_QUEUE_SIZE) as NotifySendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as NotifyReceiveQueueC;
	
	SRTreeC.Boot->MainC.Boot;
	
	SRTreeC.RadioControl -> ActiveMessageC;

	SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;
	SRTreeC.NeaMetrisi -> NeaMetrisiC;
	SRTreeC.NotifyParentTimer -> NotifyParentTimerC;

	SRTreeC.SendRootingTimer -> SendRootingTimerC;
	SRTreeC.SendParentTimer -> SendParentTimerC;


	SRTreeC.RandomNumber ->RandomC;

	SRTreeC.RoutingPacket->RoutingSenderC.Packet;
	SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;
	SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
	SRTreeC.RoutingReceive->RoutingReceiverC.Receive;
	
	SRTreeC.NotifyPacket->NotifySenderC.Packet;
	SRTreeC.NotifyAMPacket->NotifySenderC.AMPacket;
	SRTreeC.NotifyAMSend->NotifySenderC.AMSend;
	SRTreeC.NotifyReceive->NotifyReceiverC.Receive;
	
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;
	SRTreeC.NotifySendQueue->NotifySendQueueC;
	SRTreeC.NotifyReceiveQueue->NotifyReceiveQueueC;

}
