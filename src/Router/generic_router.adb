--
-- Framework: Uwe R. Zimmer
-- Examinee:  Suowei Hu
-- Reference:
--    Discussion of routing table mechinism with student      Xiangyu Hui
--    Discussion of main-task queueing mechinism with student Kent Leung
--

with Exceptions; use Exceptions;
with Queue_Pack_Protected_Generic;

package body Generic_Router is

   -- =================================
   -- ------ QUEUE FOR RELAY-MSG ------
   -- =================================
   type QueueSize_MsgRelay is mod 100;
   package Queue_Message_Relay is
     new Queue_Pack_Protected_Generic (Element  =>  Message_Relay, Index  =>  QueueSize_MsgRelay);

   -- =================================
   -- ----- QUEUE FOR RELAY-MSG -------
   -- =================================
   type QueueSize_MsgTable is mod 100;
   package Queue_Message_RoutingTable is
     new Queue_Pack_Protected_Generic (Element  =>  Message_RoutingTable, Index  =>  QueueSize_MsgTable);

   -- =================================
   -- ----- ROUTER TASK <MAIN>  -------
   -- =================================
   task body Router_Task is
      -- === PRE-DEFINED
      Connected_Routers    : Ids_To_Links;
      -- === MSG-QUEUES
      Relay_Queue          : Queue_Message_Relay.Protected_Queue;          -- Message awaiting to be relayed
      Received_Queue       : Queue_Message_Relay.Protected_Queue;          -- Message that arrived at destination
      -- === ROUTING-TABLE
      BoardCasting_Delay   : constant Standard.Duration := Standard.Duration (10.0);        -- Delay between every boardcasting of table
      Local_RoutingTable   : RoutingTable := (others  =>  (Natural'Last - 1, Task_Id, True)); -- Local Instance of "Routing Table"
      Routing_Queue        : Queue_Message_RoutingTable.Protected_Queue;   -- Message of updating "Routing Table"
   begin
      -- ==== INIT-TABLE / CONFIG-NEIGHBORS
      Local_RoutingTable (Task_Id).HopDist := 0;
      accept Configure (Links : Ids_To_Links) do Connected_Routers := Links; end Configure;
      -- ==== VAR / MAIN-TASK / SUB-TASK DECLARATION
      declare
         Port_List : constant Connected_Router_Ports := To_Router_Ports (Task_Id, Connected_Routers);

         -- ---------------------------------
         -- --- <Message Relay> SUB-TASK  ---
         -- ---------------------------------
         -- This sub-task will dequeue the last message from the relay message queue
         -- and handle it with the following rule:
         -- @ CON-1: in case the current router is the destination of the message
         --         (do nothing, it will have been handled in the main task)
         -- @ CON-2: in case the current router is not destination, then look up from the routing table and do forward to the closest next hop
         --         (if such next hop router can be found)
         -- # CON-3: in case the current router is not destination, if no such next hop router can be found on the routing table, requeue the message
         --         (such that it is not lost, and can be handled later when the routing table is updated/enhanced)

         task RouterTask_Relay;
         task body RouterTask_Relay is
            MsgRelay : Message_Relay;
         begin
            loop
               Relay_Queue.Dequeue (MsgRelay);
               -- not[Condition-1]
               if Local_RoutingTable (MsgRelay.Destination).HopNext /= Task_Id then
                  -- [Condition-2]
                  if Local_RoutingTable (MsgRelay.Destination).HopNext /= Router_Range'Invalid_Value then
                     Connected_Routers (Local_RoutingTable (MsgRelay.Destination).HopNext).all.Relay_Message (MsgRelay);
                  -- [Condition-3]
                  else
                     Relay_Queue.Enqueue (MsgRelay);
                  end if;
               end if;
            end loop;
         end RouterTask_Relay;

         -- ---------------------------------
         -- --- <Table Update> SUB-TASK  ---
         -- ---------------------------------
         -- This sub-task will dequeue the last element from the routingtable message
         -- queue, and handle the update, changing the local instance of routingtable
         -- using that message (from one of its neighbors), as well as board casting
         -- message onward in case any changes is made.
         -- Note:
         --  A routing table row is updated if either:
         --  @ CON-1: Using the neighbor as the intermediate will result closer distance (num_hop)
         --  @ CON-2: A node is now shut down (TODO: HANDLE THIS)

         task RouterTask_TableUpdate;
         task body RouterTask_TableUpdate is
            MsgTable  : Message_RoutingTable;
            NewTable : RoutingTable;
            Sender   : Router_Range;
            UpdMade  : Boolean := False;
         begin
            loop
               -- [Dequeue]
               Routing_Queue.Dequeue (MsgTable);
               NewTable := MsgTable.Table;
               Sender   := MsgTable.Sender;
               -- [Update]
               for idx in Local_RoutingTable'Range loop
                  if (NewTable (idx).HopDist + 1) < Local_RoutingTable (idx).HopDist then
                     UpdMade := True;
                     Local_RoutingTable (idx).HopDist := NewTable (idx).HopDist + 1;
                     Local_RoutingTable (idx).HopNext := Sender;
                  end if;
               end loop;
               -- [Boardcast]
               if UpdMade then
                  for Port of Port_List loop
                     Port.Link.all.TableUpdate_Message ((Task_Id, Local_RoutingTable));
                  end loop;
                  UpdMade := False;
               end if;
            end loop;
         end RouterTask_TableUpdate;

         -- ---------------------------------
         -- - <Table Period Share> SUB-TASK -
         -- ---------------------------------
         -- This sub-task will board cast the local instance of routing table
         -- the current routing table stores to its neighboring routers , and
         -- it also acts alike the initialization code for routing table.

         task RouterTask_TableBoardCast;
         task body RouterTask_TableBoardCast is
         begin
            loop
               -- [Init/Rest of neighb]
               for Port of Port_List loop
                  if Local_RoutingTable (Port.Link.all.Task_Id).Enabled then
                     Local_RoutingTable (Port.Link.all.Task_Id).HopDist := 1;
                     Local_RoutingTable (Port.Link.all.Task_Id).HopNext := Port.Link.all.Task_Id;
                  else
                     Local_RoutingTable (Port.Link.all.Task_Id).HopDist := Natural'Last - 1;
                     Local_RoutingTable (Port.Link.all.Task_Id).HopNext := Router_Range'Invalid_Value;
                  end if;
               end loop;
               -- [Boardcast to neighb]
               for Port of Port_List loop
                  Port.Link.all.TableUpdate_Message ((Task_Id, Local_RoutingTable));
               end loop;
               -- [Delay bef next share]
               delay BoardCasting_Delay;
            end loop;
         end RouterTask_TableBoardCast;

         -- ---------------------------------
         -- ----- <MAIN> DECLARATION  -------
         -- --------------------------------- (In below begin)
         -- The main function will take entry calls from the test program as well as its neighboring routers,
         -- and instead of handing all the workload in the main-tasks, it will queue all of the requeue into
         -- the corresponding queue, which will then be handled by its sub-tasks; Such that the main-tasks are
         -- not getting blocked by one of the request, and can't take other ones.
      begin
         loop
            select
            -- [SNED]
               accept Send_Message (Message : in Messages_Client) do
                  Relay_Queue.Enqueue ((Sender => Task_Id, Destination => Message.Destination, The_Message => Message.The_Message, Hop_Counter => 0));
                  -- [By adding into queue, the subtask RouterTask_Relay will handle it]
               end Send_Message;
            or
            -- [RECEIVE]
               when not Received_Queue.Is_Empty  =>  accept Receive_Message (Message : out Messages_Mailbox) do
                  declare LastReceived : Message_Relay;
                  begin   Received_Queue.Dequeue (LastReceived); Message := (LastReceived.Sender, LastReceived.The_Message, LastReceived.Hop_Counter); end;
                  -- [(Blocked until a message become available) dequeue/get the last message that has destination of router's id]
               end Receive_Message;
            or
            -- [RELAY]
               accept Relay_Message (Message : in Message_Relay) do
                  if Task_Id = Message.Destination then
                     Received_Queue.Enqueue ((Destination => Message.Destination, Sender => Message.Sender, Hop_Counter => Message.Hop_Counter + 1, The_Message => Message.The_Message));
                  else
                     Relay_Queue.Enqueue    ((Destination => Message.Destination, Sender => Message.Sender, Hop_Counter => Message.Hop_Counter + 1, The_Message => Message.The_Message));
                  end if;
                  -- [By adding into queue, the subtask RouterTask_Relay will handle it]
               end Relay_Message;
            or
            -- [ROUTING TABLE]
               accept TableUpdate_Message (Message : in Message_RoutingTable) do
                  Routing_Queue.Enqueue ((Sender => Message.Sender, Table => Message.Table));
                  -- [By adding into queue, the subtask RouterTask_Relay will handle it]
               end TableUpdate_Message;
            or
            -- [SHUTDOWN]
              accept Shutdown do
                  abort RouterTask_Relay;
                  abort RouterTask_TableUpdate;
                  abort RouterTask_TableBoardCast;
               end Shutdown;
               exit;
               -- [Shutdown all the sub-tasks, then the main routing task itself]
            end select;
         end loop;
      end;
   exception
      when Exception_Id : others  =>  Show_Exception (Exception_Id);
   end Router_Task;

end Generic_Router;
