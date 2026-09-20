using System;
using System.IO;
using System.Text.Json;

public static class CFNBridgeRecoveryTest {
    public static void Run() {
        foreach(var current in new[]{false,true}) foreach(var desired in new[]{false,true})
            if(CFNKeyboardBridge.OverlayNeedsToggle(current,desired)!=(current!=desired)) throw new Exception("Menu visibility must be idempotent");
        foreach(var key in new[]{45,112,67}) {
            if(CFNKeyboardBridge.ReadMenuKey(new[]{"REFrameworkConfig_MenuKey_V2="+key})!=key) throw new Exception("Remapped menu key not read");
        }
        foreach(var lines in new[]{new[]{"other=45"},new[]{"REFrameworkConfig_MenuKey_V2=-1"},new[]{"REFrameworkConfig_MenuKey_V2=abc"},
            new[]{"REFrameworkConfig_MenuKey_V2=45","REFrameworkConfig_MenuKey_V2=46"}})
            if(CFNKeyboardBridge.ReadMenuKey(lines)!=-1) throw new Exception("Invalid menu key accepted");
        if(CFNKeyboardBridge.Validate("t","t","new",null,45,10,true,true,false,true)!="ready") throw new Exception("Cannot hand off input");
        if(CFNKeyboardBridge.Validate("t","t","new",null,45,10,false,true,false,true)!="focus_lost") throw new Exception("Handoff escaped foreground guard");
        if(CFNKeyboardBridge.Validate("t","t","new",null,67,10,true,true,false)!="close_overlay") throw new Exception("Gameplay keys bypassed overlay");
        foreach (var error in new Exception[] {new UnauthorizedAccessException("blocked"), new IOException("locked"), new JsonException("partial")}) {
            int attempts=0;
            Action iteration=()=>{ attempts++; if (attempts==1) throw error; };
            if (CFNKeyboardBridge.TryFileIteration(iteration)) throw new Exception("Expected failed iteration");
            if (!CFNKeyboardBridge.TryFileIteration(iteration) || attempts!=2) throw new Exception("Worker cannot recover");
        }
        bool failed=false;
        try { CFNKeyboardBridge.TryFileIteration(()=>throw new InvalidOperationException("fatal")); }
        catch (InvalidOperationException) { failed=true; }
        if (!failed) throw new Exception("Unexpected errors must not be swallowed");
        string consumed=null;
        int presses=0;
        Action responseDenied=()=>{
            if (consumed=="one") return;
            consumed="one";
            presses++;
            throw new UnauthorizedAccessException("response replacement denied");
        };
        if (CFNKeyboardBridge.TryFileIteration(responseDenied)) throw new Exception("Expected receipt failure");
        if (!CFNKeyboardBridge.TryFileIteration(responseDenied) || presses!=1) throw new Exception("Consumed input was retried");
        if (CFNKeyboardBridge.Validate("t","t","new",consumed,67,600,true,false,false)!="expired")
            throw new Exception("Old input survived file recovery");
    }
}
