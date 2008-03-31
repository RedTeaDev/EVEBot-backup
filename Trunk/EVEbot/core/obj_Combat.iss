 #ifndef __OBJ_COMBAT__
 #define __OBJ_COMBAT__

/*
    The combat object
    
    The obj_Combat object is a bot-support module designed to be used
    with EVEBOT.  It provides a common framework for combat decissions
    that the various bot modules can call.
    
    USAGE EXAMPLES
    --------------
    
    objectdef obj_Miner
    {
        variable obj_Combat Combat
        
        method Initialize()
        {
            ;; bot module initialization
            ;; ...
            ;; ...
            ;; call the combat object's init routine
            This.Combat:Initialize
            ;; set the combat "mode"
            This.Combat:SetMode["DEFENSIVE"]
        }
        
        method Pulse()
        {
            if ${EVEBot.Paused}
                return
            if !${Config.Common.BotModeName.Equal[Miner]}
                return
            ;; bot module frame action code
            ;; ...
            ;; ...
            ;; call the combat frame action code
            This.Combat:Pulse
        }
        
        function ProcessState()
        {               
            if !${Config.Common.BotModeName.Equal[Miner]}
                return
            
            ; call the combat object state processing
            call This.Combat.ProcessState
            
            ; see if combat object wants to 
            ; override bot module state.
            if ${This.Combat.Override}
                return
                        
            ; process bot module "states"
            switch ${This.CurrentState}
            {
                ;; ...
                ;; ...
            }
        }       
    }
    
    COMBAT OBJECT "MODES"
    ---------------------
    
        * DEFENSIVE -- If under attack (by NPCs) AND damage taken exceeds threshold, fight back
        * AGGRESSIVE -- If hostile NPC is targeted, destroy it
        * TANK      -- Maintain defenses but attack nothing
        
        NOTE: The combat object will activate and maintain your "tank" in all modes.  
              It will also manage any enabled "flee" state.

    -- GliderPro    
*/

objectdef obj_Combat
{
	variable time NextPulse
	variable int PulseIntervalInSeconds = 5

    variable bool   Override
    variable string CombatMode
    variable string CurrentState
    variable bool   Fled
    
    method Initialize()
    {
        This.CurrentState:Set["IDLE"]
        This.Fled:Set[FALSE]
        UI:UpdateConsole["obj_Combat: Initialized"]
    }
    
    method Shutdown()
    {
    }
    
    method Pulse()
    {
		if ${EVEBot.Paused}
		{
			return
		}
		
	    if ${Time.Timestamp} > ${This.NextPulse.Timestamp}
		{
            This:SetState

    		This.NextPulse:Set[${Time.Timestamp}]
    		This.NextPulse.Second:Inc[${This.IntervalInSeconds}]
    		This.NextPulse:Update
        }
    }
    
    method SetState()
    {
		if ${Me.GetTargets(exists)} && ${Me.GetTargets} > 0
		{
			This.CurrentState:Set["FIGHT"]
		}
		else
		{
			This.CurrentState:Set["IDLE"]
		}
    }
    
    method SetMode(string newMode)
    {
        This.CombatMode:Set[${newMode}]
    }
    
    member:string Mode()
    {
        return ${This.CombatMode}
    }
    
    member:bool Override()
    {
        return ${This.Override}
    }
    
    function ProcessState()
    {
        This.Override:Set[FALSE]
        
        /* flee on (Social.IsSafe == FALSE) regardless of state */
        if !${Social.IsSafe}
        {
            call This.Flee
            This.Override:Set[TRUE]
        }
        elseif (!${Ship.IsAmmoAvailable} &&  ${Config.Combat.RunOnLowAmmo})
        {
            call This.Flee
            This.Override:Set[TRUE]
        }
        else
        {
            call This.ManageTank
            switch ${This.CurrentState}
            {
                case IDLE
                    break
                case FLEE
                    call This.Flee
                    This.Override:Set[TRUE]
                    break
                case FIGHT
                   call This.Fight
                   break
            }
        }
    }           
	
	function Fight()
	{
		Ship:Deactivate_Cloak[]
		; Reload the weapons -if- ammo is below 30% and they arent firing
		Ship:Reload_Weapons[FALSE]

		; Activate the weapons, the modules class checks if there's a target (no it doesn't - ct)
		Ship:Activate_StasisWebs
		Ship:Activate_Weapons
		call Ship.Drones.SendDrones
	}
    
    function Flee()
    {
        This.Fled:Set[TRUE]
        
        if ${Config.Combat.RunToStation}
        {
            call This.FleeToStation
        }
        else
        {
            call This.FleeToSafespot
        }
    }
    
    function FleeToStation()
    {
        if !${Station.Docked}
        {
            call Station.Dock
        }
    }
    
    function FleeToSafespot()
    {   
        ; Are we at the safespot and not warping?
        if ${Me.ToEntity.Mode} != 3 && !${Safespots.IsAtSafespot}
        {
            call Safespots.WarpTo
            wait 30
        }
        
        if ${Safespots.IsAtSafespot} && !${Ship.IsCloaked}
        {           
            wait 60
            ;UI:UpdateConsole["obj_Combat: DEBUG: At Safespot."]
            Ship:Deactivate_Hardeners[]
			Ship:Deactivate_Shield_Booster[]
			Ship:Deactivate_Armor_Reps[]
            Ship:Activate_Cloak[]
        }
    }
    
    method CheckTank(float ArmorPct, float ShieldPct, float CapacitorPct)
    {      
		/* see if tank checking is configured */
		if !${Config.Combat.RunOnLowTank}
		{
			return
		}
        
        if ${This.Fled}
        {
            /* don't leave the "fled" state until we regen */
            if (${ArmorPct} < 95 || ${ShieldPct} < 80 || ${CapacitorPct} < 80)
            {
                This.CurrentState:Set["FLEE"]
            }
            else
            {
                This.Fled:Set[FALSE]
                This.CurrentState:Set["IDLE"]           
            }
        }
        elseif (${ArmorPct} < ${Config.Combat.MinimumArmorPct}  || \
                ${ShieldPct} < ${Config.Combat.MinimumShieldPct} || \
                ${CapacitorPct} < ${Config.Combat.MinimumCapPct})
        {
            UI:UpdateConsole["Armor is at ${ArmorPct.Int}%: ${Me.Ship.Armor}/${Me.Ship.MaxArmor}"]
            UI:UpdateConsole["Shield is at ${ShieldPct.Int}%: ${Me.Ship.Shield}/${Me.Ship.MaxShield}"]
            UI:UpdateConsole["Cap is at ${CapacitorPct.Int}%: ${Me.Ship.Capacitor}/${Me.Ship.MaxCapacitor}"]
            UI:UpdateConsole["Fleeing due to defensive status"]
            This.CurrentState:Set["FLEE"]
        }           
    }   

    function ManageTank()
    {
        variable int Counter
        variable float ArmorPct
        variable float ShieldPct
        variable float CapacitorPct
        
        call Ship.ShieldPct
        ShieldPct:Set[${Return}]

        call Ship.ArmorPct
        ArmorPct:Set[${Return}]

        call Ship.CapacitorPct
        CapacitorPct:Set[${Return}]

        ;UI:UpdateConsole["DEBUG: Combat ${ArmorPct} ${ShieldPct} ${CapacitorPct}"]

		if (${ArmorPct} == -1 || ${ShieldPct} == -1 || ${CapacitorPct} == -1)
		{
			/* If any of these are -1, then the ship member timed out trying to retrieve 
				a valid value. Don't exit here, let the modules activate even if needless, 
				we'll be running anyway
			*/
			if !${This.Fled}
			{
				This.CurrentState:Set["FLEE"]
			}
		}

        if ${ArmorPct} < 90
        {
        	/* Turn on armor reps, if you have them */
            Ship:Activate_Armor_Reps[]
        }                
        elseif ${ArmorPct} > 98
        {
            Ship:Deactivate_Armor_Reps[]
        }
        
        ; The code below pulses your booster around the sweet spot
        if ${ShieldPct} < 70 || ${Config.Combat.AlwaysShieldBoost}
        {   /* Turn on the shield booster, if present */
            Ship:Activate_Shield_Booster[]
        }
        elseif ${ShieldPct} > 82 && !${Config.Combat.AlwaysShieldBoost}
        {
            Ship:Deactivate_Shield_Booster[]
        }               
        
        if ${CapacitorPct} < 20
        {   /* Turn on the cap booster, if present */
            Ship:Activate_Cap_Booster[]
        }
        elseif ${CapacitorPct} > 80
        {
            Ship:Deactivate_Cap_Booster[]
        }               
                
        ; Active shield (or armor) hardeners
        ; If you don't have hardeners this code does nothing.
        if ${Me.GetTargetedBy} > 0
        {
            Ship:Activate_Hardeners[]

            /* We have aggro now, yay! Let's launch some drones */
			if ${Config.Combat.LaunchCombatDrones} && \
				${Ship.Drones.DronesInSpace} == 0 && \
				!${Ship.InWarp}
			{
				Ship.Drones:LaunchAll[]
			}
        }
        else
        {
            Ship:Deactivate_Hardeners[]
        }

		This:CheckTank[${ArmorPct},${ShieldPct},${CapacitorPct}]
    }
}

#endif /* __OBJ_COMBAT__ */