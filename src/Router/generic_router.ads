--
-- Framework: Uwe R. Zimmer
-- Examinee:  Suowei Hu
-- Reference:
--    Discussion of routing table mechinism with student      Xiangyu Hui
--    Discussion of main-task queueing mechinism with student Kent Leung
--

with Generic_Message_Structures;
with Generic_Router_Links;
with Id_Dispenser;

generic

   with package Message_Structures is new Generic_Message_Structures (<>);

package Generic_Router is

   use Message_Structures;
   use Routers_Configuration;

   package Router_Id_Generator is new Id_Dispenser (Element => Router_Range);
   use Router_Id_Generator;

   type Router_Task;
   type Router_Task_P is access all Router_Task;

   package Router_Link is new Generic_Router_Links (Router_Range, Router_Task_P, null);
   use Router_Link;

   task type Router_Task (Task_Id  : Router_Range := Draw_Id) is

      -- ===========================
      -- === PRE-DEFINED ENTRIES ===
      -- ===========================

      entry Configure       (Links   :     Ids_To_Links);
      entry Send_Message    (Message :     Messages_Client);
      entry Receive_Message (Message : out Messages_Mailbox);
      entry Shutdown;

      -- ===========================
      -- ====== EXTRA ENTRIES ======
      -- ===========================
      entry Relay_Message   (Message : Message_Relay);             -- Function in Brief: Takes a relay message and forward it to the corresponding message router                 (more detail in adb file)
      entry TableUpdate_Message (Message : Message_RoutingTable);  -- Function in Brief: Receives a routing table from a neighbor and update its local instance of routing table  (more detail in adb file)

   end Router_Task;
end Generic_Router;
