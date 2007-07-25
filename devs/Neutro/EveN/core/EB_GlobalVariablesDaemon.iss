;; global variables (used in UI display)
variable(global) string EVEBOT_CharacterName
variable(global) string EVEBOT_MyTarget
variable(global) string EVEBOT_MyRace
variable(global) string EVEBOT_MyCorp
variable(global) int EVEBOT_TotalRuns = 0						/* Total Times We've had to transefer to hanger */


function main(string ParentName)
{
   ;; This script is launched by EVEBot and runs until EVEBot ends!
 
 	 ; Some variables just aren't going to change...they should be set initially and left alone
 	 EVEBOT_MyRace:Set[${Me.ToPilot.Type}]
 	 EVEBOT_CharacterName:Set[${Me.Name}]
 	 EVEBOT_MyCorp:Set[${Me.Corporation}]
   
   ; Otherwise, we will check every 40 frames to see if anything has changed...
   do
   {
      if (${Me.ActiveTarget(exists)})
   			EVEBOT_MyTarget:Set[${Me.ActiveTarget}]
		  else
		    EVEBOT_MyTarget:Set[None]
   
   		wait 40
   }
   while (${Script[${ParentName}](exists)} && ${ISXEVE(exists)})

}