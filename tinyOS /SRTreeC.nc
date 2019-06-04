#include "SimpleRoutingTree.h"
#include <time.h>

module SRTreeC
{
	uses interface Boot;
	uses interface SplitControl as RadioControl;


	uses interface Packet as RoutingPacket;
	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;
	
	uses interface AMSend as NotifyAMSend;
	uses interface AMPacket as NotifyAMPacket;
	uses interface Packet as NotifyPacket;

	uses interface Timer<TMilli> as RoutingMsgTimer;
	uses interface Timer<TMilli> as NeaMetrisi;
	uses interface Timer<TMilli> as NotifyParentTimer;


	uses interface Timer<TMilli> as SendRootingTimer;	//tixaiotita sto send
	uses interface Timer<TMilli> as SendParentTimer;	//tixaiotita sto anevasma

	

	uses interface Random as RandomNumber;
	
	uses interface Receive as RoutingReceive;
	uses interface Receive as NotifyReceive;
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	
	uses interface PacketQueue as NotifySendQueue;
	uses interface PacketQueue as NotifyReceiveQueue;

}
implementation
{
	//arxikopoiisi
	uint16_t sum_S=0;
	uint16_t sum_D=0;
	uint16_t count_S=1;
	uint16_t max_min_count=0;
	uint16_t max_min=0;
	uint16_t min_S=0;

	uint8_t leef=1; // otan dextei kapoia dedomena prepei apla na metadosei ta proigoumena
	uint16_t childcounter=0;


    // tipoi info table opou info table ena struct sto SimpleRoutingTree.h
	//o pinakas pou kratame ta dedomena ton paidion 
	InfoTable keepData[33];// ta nea dedomena 
	InfoTable lastTime[33];// ta dedomena ton paidion apo tin proigoumeni fora
	uint8_t pivot=0;

	bool checksend=FALSE;
	bool checkroot=FALSE;
	
	message_t radioRoutingSendPkt; //minimata gia routing
	message_t radioNotifySendPkt; //metabliti minima gia notify msg
		
	bool RoutingSendBusy=FALSE;
	bool RoutingReceiveBusy=FALSE;

	bool NotifySendBusy=FALSE;
	
	uint8_t curdepth;		// to vathos tou komvou
	uint16_t parentID;		// to id tou patera tou komvou


	uint8_t compine;
	uint16_t randomnn;		//metrisi tou aisthitira
	uint8_t epilErot;		// epilogi erotimatos
	uint8_t num;		//plithos sinartisewn pou ilopoioume
	uint8_t sinart1,sinart2;	//noumero ton sinartisewn 1...6
	//ARITMOS SINARTISEWN 
	// 1 - SUM 
	// 2 - AVG / (SUM/COUNT)
	// 3 - MAX
	// 4 - MIN
	// 5 - COUNT
	// 6 - VARIANCE


	//tasks
	task void sendRoutingTask();
	task void sendNotifyTask();
	task void receiveRoutingTask();
	task void receiveNotifyTask();

	
	void setRoutingSendBusy(bool state)
	{
		atomic{
		RoutingSendBusy=state;
		}
	}
	//analoga to bool state ginetai busy i oxi me tin klisi 
	void setNotifySendBusy(bool state)
	{
		atomic{
		NotifySendBusy=state;
		}
		dbg("SRTreeC","NotifySendBusy = %s\n", (state == TRUE)?"TRUE":"FALSE");
	}

	event void Boot.booted()	//to event pou kaleite otan theloume na kanoume boot tous komvous
	{
		uint16_t counttt;
		/////// arxikopoiisi radio 
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE); //kanoume klisi auton to duo gia na dwsoume false arxikopoiisi sto 
		setNotifySendBusy(FALSE);  //busy 
		call NeaMetrisi.startPeriodic(TIMER_NEW_INFO);	// kathe 60 depterolepta nea metrisi
		//60 depterolepta kathe epoxi -- mia fora kathe epoxi printaroume ena max,ena average ston komvo 0
		if(TOS_NODE_ID==0) //an eimai ston komvo miden printarw to vathos kai ton patera toy 
		{
			curdepth=0;
			parentID=0;//o pateras arxikopoieitai miden afou den iparxei
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
		else
		{   //an den eisai ston proto komvo kai kanei boot girna oti kati pige strava me -1 kai -1
			curdepth=-1;
			parentID=-1;                                                               //?
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}

		counttt=0; //arxikopoisi 
		do {
			lastTime[counttt].number_child=50; //paw kai arxikopoiw gia ola ta dedomena ta palia tin metabliti toy struct 50
			keepData[counttt].number_child=50; // to idio kai gia ta kainourgia .
			counttt++;
		}while(counttt<=32); //epeidi oi pinakes mas einai 33 stoixeion (0..32)
		keepData[32].max=0; //gemizw ton pinaka gia ta max me midenika san arxikopoisi 
	}
	
	event void RadioControl.startDone(error_t err)
	{
		if (err == SUCCESS) //edw ginontai initialize oi komvoi 
		{
			dbg("Radio" , "Radio initialized successfully!!!\n");
			if (TOS_NODE_ID==0)
			{
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);	// ean einai o komvos 0 ksekiname na stelnoume to 
			}			//rooting message
		}
		else
		{
			dbg("Radio" , "Radio initialization failed! Retrying...\n");
			call RadioControl.start(); //allios anoigoume to radio kai perimenoume ta to minima apo toys apo pano komvous
		}
	}
	
	event void RadioControl.stopDone(error_t err) //klisimo radio
	{ 
		dbg("Radio", "Radio stopped!\n");
	}

	
    //kaletai sto telos tis receiveNotifyTask KAI  apla kalei tin sendNotifyTask

	event void SendParentTimer.fired(){ //to event pou stelnei minimata pros ta panw

		post sendNotifyTask(); //sinartisi pou iolopoiei auti tin leitourgia 
	}

	event void SendRootingTimer.fired(){
		post receiveRoutingTask();
	}
	
	event void RoutingMsgTimer.fired()	//otan teleiosei o timer tou komvou 0 tote arxizei auto to event
	{
		message_t tmp;
		error_t enqueueDone;
		RoutingMsg* mrpkt;
		uint16_t tmpcounter=0;


		dbg("SRTreeC", "RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");
		
		if (TOS_NODE_ID==0)
			{
				dbg("SRTreeC", "\n ##################################### \n");
				dbg("SRTreeC", "#######   WE START TO INITIALIZE THE NODES    ############## \n");
				dbg("SRTreeC", "#####################################\n");
	

				epilErot=(time(NULL)%2)+1;
				if (epilErot==1)
				{
					//otan exw epilogi erwtamatos to ena --->me ti pliroforia katevainei to minima(gia tis sinartiseis).

					num= ((call RandomNumber.rand16()+6*time(NULL))%2)+1; //we get random number of the sequence between the range of 0 and 2
					switch(num)
					{	
						case 1: //an to plithos ton sinartisewn einai 1 tote
						sinart1= ((call RandomNumber.rand16()+(time(NULL)))%6)+1; //i sinartisi pernei tix arithmo 1 me 6
						dbg("Test","THE SIN IS %d\n",sinart1);
						break;
						case 2://an einai duo i sinartiseis pou tha ektelesei o aisthitiras 
						sinart1=((call RandomNumber.rand16()*(time(NULL)))%6)+1;//tixaia timi me vasei ton xrono tou sistimatos
						sinart2=((321*(time(NULL)))%6)+1;	//me tin time pernoume ton xrono tou sistimatos gia na dwsei kati diaforetiko sti 2

						//einai sigoura diaforetikes oi times giati proigoumenos pou den eixame to time (null) eixame paropoies times 
						//xrisimopoiontas ton xrono tou simulation.

						dbg("Test","THE SIN IS %d\n",sinart1);
						dbg("Test","THE SIN IS %d\n",sinart2);
						break;	
					}
					if(sinart1>sinart2){	//make sure that we always have the small number upfront
						uint16_t temp1=sinart1;
						sinart1=sinart2;               //swap
						sinart2=temp1;
					}
					//sta prota 4 mpainei i sinartisi1 kai sta alla i sinartisi2 afou xwrane sta 4bit. 
					compine=  (sinart1 << 4) | sinart2;// compress!!
				}else
				{
				    //kommati kodika sto opoio ginetai tixaia epilogi gia to poia sinartisi tha trexei sto tina 
					//kathws katevenei to routing msg pros ta katw

					num=((call RandomNumber.rand16()+6*time(NULL))%4)+1; //we get random number of the sequence between the range of 0 and 2
					sinart1=0;
					epilErot=10;
					if (num==1)
					{
						sinart2=1;
					}else if (num==2)	//giati exoume orisei alla noumera sto 2o erotima
					{
						sinart2=3;
					}else if (num==3)
					{
						sinart2=4;
					}else{
						sinart2=5;
					}
					compine= (epilErot << 4 ) | sinart2;
					epilErot=2;
				}
			

			}	
		
		// mrpkt is RootingMsg pointer initiallized above
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL) //an den parei minima tote error
		{
			dbg("SRTreeC","RoutingMsgTimer.fired(): No valid payload... \n");
			return;
		}
		atomic{
		mrpkt->senderID=TOS_NODE_ID;
		mrpkt->depth = curdepth;
		mrpkt->choicenumb= compine;// ekxwrisi tis timis tou compine ston 8bit choicenumb pou krataei tin pliroforia
		//gia tis sinartiseis .
		}
		dbg("SRTreeC" , "Sending RoutingMsg... \n");

		
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		
		enqueueDone=call RoutingSendQueue.enqueue(tmp);//vazei to minima stin send queue gia to routing minima
		
		if( enqueueDone==SUCCESS)//an egine epitixos
		{
			if (call RoutingSendQueue.size()==1)//kai exei mesa ena stoixeio to send queue gia to routing minima 
			{
				dbg("SRTreeC", "SendTask() posted!!\n");
				post sendRoutingTask(); //steilto
			}
			
			dbg("SRTreeC","RoutingMsg enqueued successfully in SendingQueue!!!\n");
		}
		else
		{
			dbg("SRTreeC","RoutingMsg failed to be enqueued in SendingQueue!!!");
		}		
	}

	event void NeaMetrisi.fired()	//otan xtipaei exoume metrisi
	{

		uint16_t randomnn8;
		uint32_t timer_start= 50000 - (130*curdepth); //timer etsi wste kathe epipedo na xtipa se allo xrono me vazei to vathos
		uint16_t tmpcounter=0;

		do{
			//kanei tin nea timi palia 
			lastTime[tmpcounter].number_child= keepData[tmpcounter].number_child;
			lastTime[tmpcounter].sum=keepData[tmpcounter].sum;
			lastTime[tmpcounter].ab= keepData[tmpcounter].ab;
			tmpcounter++;
		}while(tmpcounter<33);

		checksend=FALSE;
        //i metrisi tou aisthitira tixaia apo 0 ws 50
		randomnn= ((call RandomNumber.rand16())%50)+1; //we get random number of the sequence between the range of 0 and 50
		dbg("Gregory","The rand16 metrisi tou aisthitima is %d \n",randomnn);
		max_min_count=randomnn;
		count_S=1;
		sum_S=randomnn;
		min_S=randomnn;
		sum_D=randomnn*randomnn; //x^2 xrisi stin diaspora
		max_min=randomnn;

        //xroniki kathisterisi stin apostoli tou minimatos pros ta panw gia na apofigoume sigkrouseis.
		randomnn8= ((call RandomNumber.rand16())%20)+1; //we get random number of the sequence between the range of 0 and 5
		call NotifyParentTimer.startOneShot(timer_start+randomnn8);
	}

	event void NotifyParentTimer.fired()	//otan varesei o metritis toy arxizei na stelei ena minima pros ton patera
	{
		message_t tmp;


		if ((call NotifyReceiveQueue.empty())==TRUE && leef==1)	//paei na pei oti eimase fila opote den exei dextei kapoio allo akoma  call NotifySendQueue.empty()
		{


			dbg("Gregory", "NotifyParentMsg fired! \n");
            
			if ((sinart1==0)||(sinart2==0))//gia na mpei se ayto to if tha prepei na exw mia mono sinartisi na leitourgei
			{
				//ola ginontai simfwna me to arxiko pinakaki pou exoume kanei parapanw 

				if(sinart2==1||sinart1==1)// kanw to upologismo SUM
				{
					BigInfoSum* mrpkt; //mrpkt pointer se struct sto Simpleroutingtree.h (to minima mas)
					mrpkt = (BigInfoSum*) (call NotifyPacket.getPayload(&tmp, sizeof(BigInfoSum)));//pernw to minima
					atomic
					{
						mrpkt->data9= randomnn;//ekxwrw tin metrisi tou aisthitira mesa sto pedio tou struct
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);//pou to stelnw to minima(ston patera)
					call NotifyPacket.setPayloadLength(&tmp,sizeof(BigInfoSum));//to mikos tou minimatos pou stelnw
					keepData[32].sum= randomnn;//kai paw kai kataxwrw ston pinaka me ta kainourgai dedomena tin timi sto pedio sum

				}	
				else if (sinart2==2||sinart1==2)//ipologismos AVG (sum/count)
				{
					BigInfo* mrpkt;
					mrpkt = (BigInfo*) (call NotifyPacket.getPayload(&tmp, sizeof(BigInfo)));//pername to tipo tou minimatos
					atomic
					{
						mrpkt->data7= randomnn; //metrisi
						mrpkt->data8= 1; //epeidi eimaste sto filo to count einai 1 
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);//pou to stelnw 
					call NotifyPacket.setPayloadLength(&tmp,sizeof(BigInfo));//to megethos tou minimatos 
					}
				else if (sinart2==5||sinart1==5)//ipologismos tou count 
				{
					SmallInfo* mrpkt;
					mrpkt = (SmallInfo*) (call NotifyPacket.getPayload(&tmp, sizeof(SmallInfo)));
					atomic
					{
						mrpkt->data10= 1; //eimaste sto filo ara to count=1
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);
					call NotifyPacket.setPayloadLength(&tmp,sizeof(SmallInfo));
					keepData[32].sum= 1;

				}else if (sinart1==3 || sinart2==3 || sinart2==4 || sinart1==4)//ipologismos MAX kai MIN
				{
					SmallInfo* mrpkt;
					mrpkt = (SmallInfo*) (call NotifyPacket.getPayload(&tmp, sizeof(SmallInfo)));
					atomic
					{
						mrpkt->data10= randomnn;//metrisi aisthitira
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);
					call NotifyPacket.setPayloadLength(&tmp,sizeof(SmallInfo));	
					keepData[32].sum= randomnn;//metrisi tou aisthitira eisagetai sto pinaka me ta nea dedomena.


				}else if (sinart2==6 || sinart1==6)//ipologismos diasporas
				{
					VeryVeryBigInfo* mrpkt;
					mrpkt = (VeryVeryBigInfo*) (call NotifyPacket.getPayload(&tmp, sizeof(VeryVeryBigInfo)));
					atomic
					{
						mrpkt->data= randomnn;//metrisi tou aisthitira 
						mrpkt->data2= randomnn*randomnn;//metrisi tou aisthitira sto ^2
						mrpkt->data3= 1;//to count sto filo einai 1 
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);//pou to stelnw
					call NotifyPacket.setPayloadLength(&tmp,sizeof(VeryVeryBigInfo));//to megethos tou minimatos pou stelnw	
				}
				
			}else
			{
				//se periptwsi pou kai i sinartisi 1 kai i 2 exoun timi :
				if ((sinart1==1 && (sinart2==2 || sinart2==5)) || (sinart1==2 && sinart2==5)) //(sum && (avg || count)||(avg && count))
				{
					//balame autes tis treis periptwseis mazi se mia sin8iki giati mporoume na ipologisoume
					//kai sum kai count kai avg opote xrisimopoioume ena tipo minimatos ton pio katallilo gia kathe periptwsi
					//avg=(sum/count)
					BigInfo* mrpkt;
					mrpkt = (BigInfo*) (call NotifyPacket.getPayload(&tmp, sizeof(BigInfo)));
					atomic
					{
						mrpkt->data7= randomnn; //metrisi aisthitira
						mrpkt->data8= 1; //count sto filo
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);
					call NotifyPacket.setPayloadLength(&tmp,sizeof(BigInfo));
					
				}else if (sinart1==1 && (sinart2==3 || sinart2==4)) //(sum &&(max||min))
				{
					//to idio me parapanw akrivws i idia logiki 
					//gia to sum xreiazomaste tin metrisi tou aisthitira
					//gia to max to idio 
					BigInfo* mrpkt;
					mrpkt = (BigInfo*) (call NotifyPacket.getPayload(&tmp, sizeof(BigInfo)));
					atomic
					{
						mrpkt->data7= randomnn;//tin pername tin metrisi mia gia to sum se 16bit
						mrpkt->data8= randomnn;//tin max sta 8bit (i pio megali timi einai to 50 pou xwraei sta 8bit)
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);
					call NotifyPacket.setPayloadLength(&tmp,sizeof(BigInfo));			
				}else if ((sinart1==1 || sinart1==2 || sinart1==5) && sinart2==6)//((sum||avg||count)&&variance)
				{
					//gia to sum thelw tin metrisi ,avg =sum /count,kai variance thelw avg kai x^2
					//ara o katallilos tipos minimatos gia ayto einai o parakatw
					VeryVeryBigInfo* mrpkt;
					mrpkt = (VeryVeryBigInfo*) (call NotifyPacket.getPayload(&tmp, sizeof(VeryVeryBigInfo)));

					atomic
					{
						mrpkt->data= randomnn;//metrisi aisthitira
						mrpkt->data2= randomnn*randomnn;//metrisi aisthitira sto tetragwno
						mrpkt->data3= 1;//count sto filo 1
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);
					call NotifyPacket.setPayloadLength(&tmp,sizeof(VeryVeryBigInfo));	
				}else if ( ( sinart1==3 || sinart1==4 ) && sinart2==6)//((max||min)&&variance)
				{
					//gia to variance thelw 3 elements thelw count thelw sum kai tin metrisi sto tetragwno
					//ennow gia to max i to min apla tin metrisi 
					//ara kataligoume ston parakatw tipo minimatos
					VeryVeryVeryBigInfo* mrpkt;
					mrpkt = (VeryVeryVeryBigInfo*) (call NotifyPacket.getPayload(&tmp, sizeof(VeryVeryVeryBigInfo)));

					atomic
					{
						mrpkt->data= randomnn;//metrisi aisthitira 
						mrpkt->data2= randomnn*randomnn;//metabliti 32bit gia na xwraei to variance
						mrpkt->data3= 1;//metabliti 8 bit gia na xwraei to count 
						mrpkt->data4= randomnn;//metrisi aisthitira (max || min )8bit
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);
					call NotifyPacket.setPayloadLength(&tmp,sizeof(VeryVeryVeryBigInfo));
				}


				else if (sinart1==2 && (sinart2==3 ||sinart2==4 )) // (avg &&(max||min))
				{
					//antistoixa vriskoume ton katallilo tipo minimatos analoga me to ti xreiazomaste
					//metrisi aisth gia parw sum ,count kai min i max
					VeryBigInfo* mrpkt;
					mrpkt = (VeryBigInfo*) (call NotifyPacket.getPayload(&tmp, sizeof(VeryBigInfo)));
					atomic
					{
						mrpkt->data4= randomnn;//metrisi aisthitira 
						mrpkt->data5= 1;//count sto filo 1
						mrpkt->data6= randomnn;//metrisi aisthitira gia gia max min
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);
					call NotifyPacket.setPayloadLength(&tmp,sizeof(VeryBigInfo));
				}else if (sinart1==3 && sinart2==4)//(min && max)
				{
					TwoSmallInfo* mrpkt;
					mrpkt = (TwoSmallInfo*) (call NotifyPacket.getPayload(&tmp, sizeof(TwoSmallInfo)));
					atomic
					{
						mrpkt->data11= randomnn;//metrisi aisthitira ipol (min) 8bit
						mrpkt->data12= randomnn;//metrisi aisthitira  ipol (max) 8bit
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);
					call NotifyPacket.setPayloadLength(&tmp,sizeof(TwoSmallInfo));
				}else if ((sinart1==3 || sinart1==4) && sinart2==5)//((min||max)&&count)
				{
					TwoSmallInfo* mrpkt;
					mrpkt = (TwoSmallInfo*) (call NotifyPacket.getPayload(&tmp, sizeof(TwoSmallInfo)));
					atomic
					{
						mrpkt->data11= randomnn;//metrisi aisthitira i gia min i gia max
						mrpkt->data12= 1;//count sto filo 1
					}
					call NotifyAMPacket.setDestination(&tmp, parentID);
					call NotifyPacket.setPayloadLength(&tmp,sizeof(TwoSmallInfo));
				}
			}
			call NotifySendQueue.enqueue(tmp); //vazw to teliko minima pou tha steilw stin notifySend Queue
			post sendNotifyTask(); // kai to stelnw me tin send notify.

				
			
		}else{ //an den eimai sta fila kai i receive notify queue den einai adeia 
			pivot=0;	//ksanagirname to pivot na dixnei stin arxi
			post receiveNotifyTask(); //kalw ayti gia na sinexisei tin idia diadikasia gia tous endiamesous komvous.
			leef=0; 
		}
	}



	
	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		dbg("SRTreeC", "A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");
		dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");
		setRoutingSendBusy(FALSE);
		
		if(!(call RoutingSendQueue.empty()))
		{
			uint16_t randomnn2= ((call RandomNumber.rand16())%10)+1; //we get random number of the sequence between the range of 0 and 5
			call SendRootingTimer.startOneShot(randomnn2);
		}	
	}
	
	event void NotifyAMSend.sendDone(message_t *msg , error_t err)
	{
		dbg("SRTreeC", "A Notify package sent... %s \n",(err==SUCCESS)?"True":"False");
		
	
		dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");
		setNotifySendBusy(FALSE);
		checksend=TRUE;
	
		if(!(call NotifySendQueue.empty()))
		{
			post sendNotifyTask();
		}
	
	}

	
	
	event message_t* NotifyReceive.receive( message_t* msg , void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		

		
		msource = call NotifyAMPacket.source(msg);
		
		dbg("SRTreeC", "### NotifyReceive.receive() start ##### \n");
		dbg("Gregory", "Something received!!!  from    %u \n", msource);
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		}
		keepData[childcounter].number_child=msource;
		keepData[childcounter].ab= tmp;
		enqueueDone=call NotifyReceiveQueue.enqueue(tmp);
		childcounter++;
		dbg("SRTreeC", "### NotifyReceive.receive() end ##### \n");
		return msg;

	}

	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)//otan lavw rooting message
	{	

		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;



		
		msource =call RoutingAMPacket.source(msg);
		
		dbg("SRTreeC", "### RoutingReceive.receive() start ##### \n");
		dbg("SRTreeC", "Something received!!!  from %u  %u \n",((RoutingMsg*) payload)->senderID ,  msource);
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			call SendRootingTimer.startOneShot(10);	//dinoume xrono na lavei 10ms
		}
		else
		{
			dbg("SRTreeC","RoutingMsg enqueue failed!!! \n");	
		}		
		dbg("SRTreeC", "### RoutingReceive.receive() end ##### \n");
		return msg;
	}
	////////////// Tasks implementations //////////////////////////////
	
	//we use this task to send the message to the children --RootingMsg
	task void sendRoutingTask()
	{
		
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		
		//we check if the Send Queue is empty
		if (call RoutingSendQueue.empty())
		{
			dbg("SRTreeC","sendRoutingTask(): Q is empty!\n");
			return;
		}
		
		
		if(RoutingSendBusy)
		{
			dbg("SRTreeC","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue(); //pernei to prwto stoixeio
		
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);// to mikos tou
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);//to pou einai 
		if(mlen!=sizeof(RoutingMsg))
		{
			dbg("SRTreeC","\t\tsendRoutingTask(): Unknown message!!!\n");
			return;
		}
		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("SRTreeC","sendRoutingTask(): Send returned success!!!\n");
			setRoutingSendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");
		}
	}
	/**
	 * dequeues a message and sends it
	 */

	//we use this task to send the message to the parent -- NotifyParentMsg
	task void sendNotifyTask()
	{
		uint8_t mlen;//, skip;
		error_t sendDone;
		uint16_t mdest;

		
		if (call NotifySendQueue.empty()) //an i lista tou komvou pou exei minimata pros apostoli einai adeia
		{
			dbg("Gregory","sendNotifyTask(): Q is empty!\n");
			return; 
		}
		
		if(NotifySendBusy==TRUE)
		{
			dbg("SRTreeC","sendNotifyTask(): NotifySendBusy= TRUE!!!\n");
			return;
		}

		if (epilErot==2)  // an TINA 
		{
			float_t diafora;
			dbg("Gregory","keepData is %d \n",keepData[32].sum);
			dbg("Gregory","lastTime is %d \n",lastTime[32].sum);
			if (lastTime[32].sum!=0)
			{
				diafora= (float_t) (abs(keepData[32].sum-lastTime[32].sum))/lastTime[32].sum;
				diafora= diafora*100;
				dbg("Gregory","diafora is %f \n",diafora);
			}
			

			if (diafora<=15 && lastTime[32].sum!=0) //to diaforo?
			{
				return;
			}			
		}

		
		radioNotifySendPkt = call NotifySendQueue.dequeue(); // pernw to prwto stoixeio apo tin lista gia apostoli kai to vazw seena meesage
		mlen=call NotifyPacket.payloadLength(&radioNotifySendPkt); //pernw to megethos toy message
		
		call NotifyPacket.getPayload(&radioNotifySendPkt,mlen);//pernw olo to minima 
		
		
		dbg("SRTreeC" , " sendNotifyTask(): mlen = %u   \n",mlen);
		mdest= call NotifyAMPacket.destination(&radioNotifySendPkt);
		sendDone=call NotifyAMSend.send(mdest,&radioNotifySendPkt, mlen); //kai to stelnw pros ton patera 
		
		if ( sendDone== SUCCESS)// an i apostoli egine me epitixia tote ok
		{
			dbg("Gregory","sendNotifyTask(): Send returned success!!!\n");
			setNotifySendBusy(TRUE); //kanw busy tin notifysend busy epeidi stelnei
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");
		}
	}
	////////////////////////////////////////////////////////////////////
	//*****************************************************************/
	///////////////////////////////////////////////////////////////////
	/**
	 * dequeues a message and processes it
	 */
	

	//we receive the RootingMsg from parent
	task void receiveRoutingTask()
	{
		
		message_t tmp;
		uint8_t len;
		message_t radioRoutingRecPkt;
		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue(); //pernoume apo tin oura ton minimatwn to proto minima pou exei dektei
		
		if (checkroot==TRUE) // an vriskomaste stin arxi tou dentrou den exei noima
		{
			return;
		}

		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt); //pernw to mikos tou routing message mou
		
		dbg("SRTreeC","ReceiveRoutingTask(): len=%u \n",len);
				
		if(len == sizeof(RoutingMsg)) //elegxos gia to an einai routing message
		{

			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len)); //pernw olo to minima 			
			dbg("SRTreeC" , "receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);
            //tiponw to apostolea tou minimatos tou routing kai to vathos tou.
			checkroot=TRUE;

			if ( (parentID<0)||(parentID>=65535)) //an den iarxei pateras kai eimaste ston proto komvo.
			{
				// tote den exei akoma patera
				parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;q //exei na kanei me tin pigi tou minimatos ara ton patera pou to stelnei
				curdepth= mpkt->depth + 1;//pou paei to minima se pio vathos (+1 apo auton pou to esteile)
				compine= mpkt->choicenumb; //choicenumb 8 bit ton opoio stin sinexeia ton spame 


				sinart1=(compine & 0b11110000) >> 4; //  pernw ta prwta tessera most significant bit 
				sinart2=(compine & 0b00001111); //pernw ta 4 LSB
				dbg("Gregory","The sinart1 is %d",sinart1);
				if (sinart1==10)	//simvasi :pername ston aisthitira oti dialeksame to erotima 2
				{
					epilErot=2; 
					sinart1=0; //thelw mono mia sinartisi kai to kanoume etsi 
				}
				dbg("Gregory","The sinart1 is %d\n",sinart1);
				dbg("Gregory","The sinart2 is %d\n",sinart2);
				if (TOS_NODE_ID!=0) // an den eimai stin arxi tou dentrou steile
				{
					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD); //ksekinaei na stelnei routing message
				}	
			}
		}
		else
		{
			dbg("SRTreeC","receiveRoutingTask():Empty message!!! \n");
			return;
		}
		
	}

////////////////////////////////////////////////////////////////////////	
	
	task void receiveNotifyTask()
	{
		message_t tmp;
		uint8_t len;
		uint16_t randomnn1;
		message_t radioNotifyRecPkt;
		radioNotifyRecPkt= call NotifyReceiveQueue.dequeue(); // pernoume tin proti ekpompi poy exei na kanei me ton aisthitima
		
		len= call NotifyPacket.payloadLength(&radioNotifyRecPkt);	// vlepoume to megethos tou

		if (sinart1==0||sinart2==0)	//ara exoume mia sinartisi
		{
			if (sinart1==1 || sinart2==1) //an exw sum
			{
				BigInfoSum* mr = (BigInfoSum*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len)); //pernw to minima pou stal8ike ston sigkerimeno tipo.

				sum_S= (mr->data9)+ sum_S; //kai to a8rizw sto sum opou Sum_S stin arxi einai miden exei oristei panw.

				keepData[pivot].sum=mr->data9; //paw kai apothikeuw tin timi ston pinaka me ta nea dedomena kai timi 
				//pivot 0 arxika apo tin klisi tis NotifyParentTimer.fired()

				pivot++;//kai to auksanw
 				
 			}
 			if (sinart2==2||sinart1==2)//an thelw avg
 			{
 				BigInfo* mr = (BigInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));//pernw to minima apo 
                //apo tin NotifyReceiveQueue kai to prosarmozw ston katallilo tipo minimatos
				sum_S= (mr->data7)+ sum_S;// auksanw to sum_S me vasei tin timi pou pira apo auto pou mas stal8ike
				count_S=(mr->data8)+ count_S;//to idio kanw kai gia to count 

				keepData[pivot].sum=mr->data7;//apothikeuw to sum sto pinaka ton newn dedomenwn gia sum 
				keepData[pivot].count=mr->data8;// to idio kai gia to count

				pivot++;//auksanw ton deikti tou pinaka.
 			}
 			if (sinart1==3||sinart2==3||sinart1==4||sinart2==4||sinart1==5||sinart2==5)//an thelw max i min i count
 			{
				SmallInfo* mr = (SmallInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
                //EURESI_MAX
				if (sinart1==3||sinart2==3) //(sin1==max ||sin2==max) mia ap tis duo tha einai alla to genikeuoume
				{
					if (max_min_count<mr->data10) //mr->data10 i timi tou minimatos pou pernoume ,an einai megalitero
					{
						max_min_count= mr->data10; //kane max auto
					}	
				}//EURESI_MIN
				else if (sinart1==4||sinart2==4)//an kai oi dio sinartiseis einai  gia min (mia ap tis duo tha einai alla to genikeuoume)
				{//leiourgoume antistoixa
					if (max_min_count>mr->data10)
					{
						max_min_count= mr->data10;
					}
				}
				else{ //alliws pame gia euresi count
					count_S=(mr->data10)+ count_S;
				}
				keepData[pivot].max= mr->data10; //kathe fora edw mesa apothikeuetai i timi pou theloume na ipologisoume vasi ton parapanw conditions
				pivot++;//auksanw ton deikti tou pinaka.

			}else if (sinart1==6 || sinart2==6)//an thelw na ipologisw to variance
			{
				//pernw to minima pou stal8ike kai to kanw ston katallilo tipo.
				VeryVeryBigInfo* mr = (VeryVeryBigInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
				max_min_count= max_min_count + (mr->data);//!!! kanonika metrisi gia athrisma sum_S
				sum_D= sum_D + (mr->data2); //a8rizw ti metrisi sto teragwno
				count_S= count_S+ (mr->data3);//count to auksanw

				keepData[pivot].sum=mr->data;//pernaw to sum ston pinaka me ta nea dedomena 
				keepData[pivot].max=mr->data2;//antistoixa kai gia ta ipoloipa
				keepData[pivot].count=mr->data3;

				pivot++;
			}
				

 		}else
 		{
 			//AN EXW DYO SINARTISEIS!!!
            // I LGOIKI EINAI PAROMOIA ME AYTI TIS notifyParent.fired() otan exw dyo sinartiseis!!

 			if ((sinart1==1 && (sinart2==2 || sinart2==5)) || (sinart1==2 && sinart2==5))//(SUM &&(AVG||COUNT)||(AVG && COUNT))
 			{
				BigInfo* mr = (BigInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
                //o katallilos tipos einai o parapanw kai einai to minima pou mas stal8ike apoo tous katw komvous
				sum_S= (mr->data7)+ sum_S;//pernaw tin metrisi pou pira sto sum 
				count_S=(mr->data8)+ count_S;//pernaw kai to count

				keepData[pivot].sum=mr->data7;//paw kai kataxwrw tin timi ston pinaka me ta nea dedomena
				keepData[pivot].count=mr->data8;

				pivot++; 			//auksanw ton deikti tou pinaka 
			}else if (sinart1==1 && sinart2==3)//(SUM && MAX)
			{
				BigInfo* mr = (BigInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));

				sum_S= (mr->data7)+ sum_S;
				if (max_min_count<mr->data8)
				{
						max_min_count= mr->data8;
				}	
				keepData[pivot].sum=mr->data7;
				keepData[pivot].count=mr->data8;

				pivot++;

			}else if (sinart1==1 && sinart2==4)//(sum && min)
			{
				BigInfo* mr = (BigInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));

				sum_S= (mr->data7)+ sum_S;
				if (max_min_count>mr->data8)
				{
						max_min_count= mr->data8;
				}	
				keepData[pivot].sum=mr->data7;
				keepData[pivot].count=mr->data8;

				pivot++;
			}else if ((sinart1==1 || sinart1==2 || sinart1==5) && sinart2==6)//((sum||avg||count)&&(variance))
			{
				VeryVeryBigInfo* mr = (VeryVeryBigInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
				max_min_count= max_min_count + (mr->data); //!!
				sum_D= sum_D + (mr->data2);
				count_S= count_S+ (mr->data3);

				keepData[pivot].sum=mr->data;
				keepData[pivot].max=mr->data2;
				keepData[pivot].count=mr->data3;

				pivot++;
			}else if ((sinart1==3 || sinart1==4 ) && sinart2==6)//((max||min)&& variance)
			{
				VeryVeryVeryBigInfo* mr = (VeryVeryVeryBigInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
				max_min_count= max_min_count + (mr->data);//sum!!
				sum_D= sum_D + (mr->data2);
				count_S= count_S+ (mr->data3);
				
				if (max_min<mr->data4 && sinart1==3)//max
				{
					max_min= mr->data4;

				}else if (max_min>mr->data4 && sinart1==4)//min
				{
					max_min= mr->data4;
				}
				

				keepData[pivot].sum=mr->data;
				keepData[pivot].max=mr->data2;
				keepData[pivot].count=mr->data3;
				keepData[pivot].min= mr->data4;

				pivot++;

			}
			else if (sinart1==2 && sinart2==3)//(AVG && MAX)
			{
				VeryBigInfo* mr = (VeryBigInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));

				sum_S= (mr->data4)+ sum_S;
				count_S=(mr->data5)+ count_S;
				if (max_min_count<mr->data6)
				{
						max_min_count= mr->data6;
				}	

				keepData[pivot].sum=mr->data4;
				keepData[pivot].count=mr->data5;
				keepData[pivot].max= mr->data6;

				pivot++;
			}else if (sinart1==2 && sinart2==4) //(AVG && MIN)
			{
				VeryBigInfo* mr = (VeryBigInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));

				sum_S= (mr->data4)+ sum_S;
				count_S=(mr->data5)+ count_S;
				if (max_min_count>mr->data6)
				{
						max_min_count= mr->data6;
				}	

				keepData[pivot].sum=mr->data4;
				keepData[pivot].count=mr->data5;
				keepData[pivot].max= mr->data6;

				pivot++;
			}else if (sinart1==3 && sinart2==4)//(MAX && MIN)
			{
				TwoSmallInfo* mr = (TwoSmallInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));

				if (max_min_count<mr->data11)
				{
						max_min_count= mr->data11;
				}	
				if (min_S>mr->data12)
				{
						min_S= mr->data12;
				}	

				keepData[pivot].max=mr->data11;
				keepData[pivot].min= mr->data12;

				pivot++;

			}else if ((sinart1==3 || sinart1==4) && sinart2==5) //((max||min)&& count)
			{
				//thelw mono dio metablites afou i tha kanw min i max thelw tin metrisi tou aisthitira
				//kai to count apo to minima pou mas stal8ike
				TwoSmallInfo* mr = (TwoSmallInfo*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));

				if (max_min_count<mr->data11 && sinart1==3) //elegxos gia max
				{
					max_min_count= mr->data11;
				}	else if (max_min_count>mr->data11 && sinart1==4)//elegxos gia min 
				{
					max_min_count= mr->data11;
				}
				count_S=(mr->data12)+ count_S;	

				keepData[pivot].max=mr->data11;
				keepData[pivot].count= mr->data12;

				pivot++;
			}

 		}
 		//---------------------------

 		if (epilErot ==2)
 		{
 			uint8_t check=0;
 			uint16_t check2=0;
 			uint16_t count12=0;


 			while (lastTime[check2].number_child!=50)
 			{
 				check=0;
 				count12=0;
 				do{
 					if (lastTime[check2].number_child== keepData[count12].number_child)
 					{
 						check=1;	
 					}
 					count12++;
 				}while(count12<pivot);
 				if (check==0)
 				{
 					dbg("Gregory","I entered the matrix with the value: %d\n",lastTime[check2].sum);
 					call NotifyReceiveQueue.enqueue(lastTime[check2].ab);
 					pivot++;
 					keepData[pivot].number_child= lastTime[check2].number_child;
 					keepData[pivot].ab= lastTime[check2].ab;

 				}
 				check2++;
 			};
 		}

		if ((call NotifyReceiveQueue.empty())==TRUE)
		{
			if (TOS_NODE_ID==0)
			{

				//dbg("Gregory","\n The beatiful SUM of our beutiful program is: %d\n\n",sum_S);
				//dbg("Gregory","The beatiful COUNT of our beutiful program is: %d\n\n",count_S);
				dbg("Gregory", "\n############################################################ \n");
				if (sinart1==0||sinart2==0)
				{
					if (sinart1==1|| sinart2==1)
					{
						dbg("Gregory","The beatiful sum of the sensors is: %d\n",sum_S);

					}else if (sinart1==2||sinart2==2)
					{
						dbg("Gregory","The beatiful SUM of the sensors is: %d\n",sum_S);
						dbg("Gregory","The beatiful average of the sensors is: %d\n",sum_S/count_S);

					}else if (sinart2==3||sinart1==3)
					{
						dbg("Gregory","The beatiful max of the sensors is: %d\n",max_min_count);
					}
					else if (sinart1==4|| sinart2==4)
					{
						dbg("Gregory","The beatiful min of the sensors is: %d\n",max_min_count);
					}
					else if (sinart1==5|| sinart2==5)
					{
						dbg("Gregory","The beatiful count of the sensors is: %d\n",count_S);
					}else if (sinart1==6 || sinart2==6)
					{
						dbg("Gregory","The beatiful var of the sensors is: %d\n",((sum_D/count_S)- (max_min_count/count_S)*(max_min_count/count_S)));

					}
				}else
				{
					if (sinart1==1 && sinart2==2)
					{
						dbg("Gregory","The beatiful SUM of the sensors is: %d\n",sum_S);
						dbg("Gregory","The beatiful average of the sensors is: %d\n",sum_S/count_S);
					}
					else if (sinart1==1 && sinart2==3)
					{
						dbg("Gregory","The beatiful SUM of the sensors is: %d\n",sum_S);
						dbg("Gregory","The beatiful MAX of the sensors is: %d\n",max_min_count);
					}else if (sinart1==1 && sinart2==4)
					{
						dbg("Gregory","The beatiful SUM of the sensors is: %d\n",sum_S);
						dbg("Gregory","The beatiful MIN of the sensors is: %d\n",max_min_count);
					}else if (sinart1==1 && sinart2==5)
					{
						dbg("Gregory","The beatiful SUM of the sensors is: %d\n",sum_S);
						dbg("Gregory","The beatiful COUNT of the sensors is: %d\n",count_S);

					}else if (sinart1==1 && sinart2==6)
					{
						dbg("Gregory","The beatiful SUM of the sensors is: %d\n",max_min_count);
						dbg("Gregory","The beatiful VAR of the sensors is: %d\n",((sum_D/count_S)- (max_min_count/count_S)*(max_min_count/count_S)));
					}
					else if (sinart1==2 && sinart2==3)
					{
						dbg("Gregory","The beatiful SUM of the sensors is: %d\n",sum_S);
						dbg("Gregory","The beatiful average of the sensors is: %d\n",sum_S/count_S);
						dbg("Gregory","The beatiful MAX of the sensors is: %d\n",max_min_count);
					}else if (sinart1==2 && sinart2==4)
					{
						dbg("Gregory","The beatiful average of the sensors is: %d\n",sum_S/count_S);
						dbg("Gregory","The beatiful MIN of the sensors is: %d\n",max_min_count);
					}
					else if (sinart1==2 && sinart2==5)
					{
						dbg("Gregory","The beatiful average of the sensors is: %d\n",sum_S/count_S);
						dbg("Gregory","The beatiful COUNT of the sensors is: %d\n",count_S);

					}else if (sinart1==2 && sinart2==6)
					{
						dbg("Gregory","The beatiful average of the sensors is: %d\n",max_min_count/count_S);
						dbg("Gregory","The beatiful VAR of the sensors is: %d\n",((sum_D/count_S)- (max_min_count/count_S)*(max_min_count/count_S)));
					}

					else if (sinart1==3 && sinart2==4)
					{
						dbg("Gregory","The beatiful MAX of the sensors is: %d\n",max_min_count);
						dbg("Gregory","The beatiful MIN of the sensors is: %d\n",min_S);
					}else if (sinart1==3 && sinart2==5)
					{
						dbg("Gregory","The beatiful MAX of the sensors is: %d\n",max_min_count);
						dbg("Gregory","The beatiful COUNT of the sensors is: %d\n",count_S);
					}else if (sinart1==3 && sinart2==6)
					{
						dbg("Gregory","The beatiful MAX of the sensors is: %d\n",max_min);
						dbg("Gregory","The beatiful VAR of the sensors is: %d\n",((sum_D/count_S)- (max_min_count/count_S)*(max_min_count/count_S)));

					}
					else if (sinart1==4 && sinart2==5)
					{
						dbg("Gregory","The beatiful MIN of the sensors is: %d\n",max_min_count);
						dbg("Gregory","The beatiful COUNT of the sensors is: %d\n",count_S);					
					}else if (sinart1==4 && sinart2==6)
					{
						dbg("Gregory","The beatiful MIN of the sensors is: %d\n",max_min);
						dbg("Gregory","The beatiful VAR of the sensors is: %d\n",((sum_D/count_S)- (max_min_count/count_S)*(max_min_count/count_S)));
					}
					else if (sinart1==5 && sinart2==6)
					{
						dbg("Gregory","The beatiful COUNT of the sensors is: %d\n",count_S);
						dbg("Gregory","The beatiful VAR of the sensors is: %d\n",((sum_D/count_S)- (max_min_count/count_S)*(max_min_count/count_S)));
						
					}
				}
				dbg("Gregory", "\n############################################################# \n\n");


				//midenizoume toys metrites
				sum_S=0;
				max_min_count=0;
				count_S=0;
			}
			else{


				if (sinart2==0||sinart1==0)
				{
					if (sinart1==1||sinart2==1)
					{
						BigInfoSum* m;
						memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
						m = (BigInfoSum *) (call NotifyPacket.getPayload(&tmp, sizeof(BigInfoSum)));

						m->data9=sum_S;

						keepData[32].sum= sum_S;

						

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(BigInfoSum));


					}else if (sinart1==2||sinart2==2)
					{
						BigInfo* m;
						memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
						m = (BigInfo *) (call NotifyPacket.getPayload(&tmp, sizeof(BigInfo)));

						m->data7=sum_S;
						m->data8=count_S;

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(BigInfo));

						
					}else if (sinart1==3||sinart2==3||sinart2==4||sinart1==4)
					{
						SmallInfo* m;
						memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
						m = (SmallInfo *) (call NotifyPacket.getPayload(&tmp, sizeof(SmallInfo)));

						m->data10= max_min_count;

						keepData[32].sum=max_min_count;

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(SmallInfo));

					}else if (sinart1==5||sinart2==5)
					{
						SmallInfo* m;
						memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
						m = (SmallInfo *) (call NotifyPacket.getPayload(&tmp, sizeof(SmallInfo)));

						m->data10= count_S;

						keepData[32].sum= count_S;

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(SmallInfo));					
					}else if (sinart2==6 || sinart1==6)
					{
						VeryVeryBigInfo* m;
						memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
						m = (VeryVeryBigInfo *) (call NotifyPacket.getPayload(&tmp, sizeof(VeryVeryBigInfo)));

						m->data=max_min_count;
						m->data2=sum_D;
						m->data3=count_S;

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(VeryVeryBigInfo));
					}



				}else{
					if ((sinart1==1 && (sinart2==2 || sinart2==5)) || (sinart1==2 && sinart2==5))
					{
						BigInfo* m;
						memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
						m = (BigInfo *) (call NotifyPacket.getPayload(&tmp, sizeof(BigInfo)));

						m->data7=sum_S;
						m->data8=count_S;

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(BigInfo));
					}
					else if (sinart1==1 && (sinart2==3 ||sinart2==4))
					{
						BigInfo* m;
						memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
						m = (BigInfo *) (call NotifyPacket.getPayload(&tmp, sizeof(BigInfo)));

						m->data7=sum_S;
						m->data8=max_min_count;

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(BigInfo));
					}else if ((sinart1==1 || sinart1==2 || sinart1==5) && sinart2==6)
					{
						VeryVeryBigInfo* m;
						memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
						m = (VeryVeryBigInfo *) (call NotifyPacket.getPayload(&tmp, sizeof(VeryVeryBigInfo)));

						m->data=max_min_count;
						m->data2=sum_D;
						m->data3=count_S;

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(VeryVeryBigInfo));
					}
					else if (sinart1==2 && (sinart2==3 || sinart2==4))
					{
						VeryBigInfo* m;
						memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
						m = (VeryBigInfo *) (call NotifyPacket.getPayload(&tmp, sizeof(VeryBigInfo)));

						m->data4=sum_S;
						m->data5=count_S;
						m->data6=max_min_count;

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(BigInfo));
					}else if ((sinart1==3 || sinart1==4) && (sinart2==4 ||sinart2==5))
					{
						TwoSmallInfo* m;
						memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
						m = (TwoSmallInfo *) (call NotifyPacket.getPayload(&tmp, sizeof(TwoSmallInfo)));

						m->data11=max_min_count;
						if (sinart2==5)
						{
							m->data12=count_S;		
						}else
						{
							m->data12=min_S;
						}

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(BigInfo));
					}else if ((sinart1==3 || sinart1==4) && sinart2==6)
					{
						VeryVeryVeryBigInfo* m;
						memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
						m = (VeryVeryVeryBigInfo *) (call NotifyPacket.getPayload(&tmp, sizeof(VeryVeryVeryBigInfo)));

						m->data=max_min_count;
						m->data2=sum_D;
						m->data3=count_S;
						m->data4=max_min;

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(VeryVeryVeryBigInfo));
					}
				}
				call NotifySendQueue.enqueue(tmp);
				randomnn1= ((call RandomNumber.rand16())%19)+1; //we get random number of the sequence between the range of 0 and 5
				call SendParentTimer.startOneShot(randomnn1);
						
			}
						
		}		
		else
		{			
			post receiveNotifyTask();
		}			
	}

}		

	
	