--
-- Framework: Uwe R. Zimmer
-- Examinee:  Suowei Hu
-- Reference:
--    Discussion of routing table mechinism with student      Xiangyu Hui
--    Discussion of main-task queueing mechinism with student Kent Leung
--

with Ada.Strings.Bounded;           use Ada.Strings.Bounded;
with Generic_Routers_Configuration;

generic
   with package Routers_Configuration is new Generic_Routers_Configuration (<>);

package Generic_Message_Structures is

   -- =============================
   -- === PRE-DEFINED MSG TYPES ===
   -- =============================

   use Routers_Configuration;
   package Message_Strings is new Generic_Bounded_Length (Max => 80);
   use Message_Strings;

   subtype The_Core_Message is Bounded_String;
   type Messages_Client is record
      Destination : Router_Range;
      The_Message : The_Core_Message;
   end record;

   type Messages_Mailbox is record
      Sender      : Router_Range     := Router_Range'Invalid_Value;
      The_Message : The_Core_Message := Message_Strings.To_Bounded_String ("");
      Hop_Counter : Natural          := 0;
   end record;

   -- =============================
   -- ====== EXTRA MSG TYPES ======
   -- =============================
   type Message_Relay is record      -- [ Message sent during the relaying process (between getting the message via send, and receiving the message via receive) ]
      Destination : Router_Range     := Router_Range'Invalid_Value;                 -- Target Router
      Sender      : Router_Range     := Router_Range'Invalid_Value;                 -- Sender Router
      Hop_Counter : Natural          := 0;                                          -- Number of forwarding done
      The_Message : The_Core_Message := Message_Strings.To_Bounded_String ("");     -- Message body
   end record;

   type Routing_Row is record        -- [ The row of the routing table, or the destination vector for when updating neighbors (via message) ]
      -- Dest : Determined through RoutingTable index    -- Destination     (IP + Mask    in formal routing table) : The desired target of the message
      HopDist : Natural := Natural'Last - 1;             -- Distance        (Cost/Metric  in formal routing table) : The number of hops to get to that destination taget (0 if self->self, 1 if neighboring, 2+ if connected via media routers)
      HopNext : Router_Range;                            -- NextHop_Router  (Gateway      in formal routing table) : Where should send as next router, such that the message reaches destination (if all intermediate nodes are available)
      Enabled : Boolean;                                 -- Is_Available    (Flag (U/D)   in formal routign table) : Whether the server is still available (not powered down)
   end record;

   type RoutingTable is                -- [ The routing table stored at the local cache of each router, used to find next hot for a target ]
      array (Router_Range)                      -- Each of the element in the routing table represent the routing information of going from "CURRENT_ROUTER" to a "DESTINATION_ROUTER", for example:
   of Routing_Row;                              -- Consider this is the routing table of "ROUTER-13", then the 20th entry of the table means the routing information about going from "ROUTER-13" to "ROUTER-20"

   type Message_RoutingTable is record -- [ The message a router will send to its neighboring routers, when its routing table is updated ]
      Sender : Router_Range;                   -- The sender of the message, used to update the "NextHop_Router"
      Table  : RoutingTable;                   -- DestinationVector
   end record;

end Generic_Message_Structures;
