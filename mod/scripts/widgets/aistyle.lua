-- Reuse the installed crafting menu artwork, not an imitation bitmap.
local Widget=require("widgets/widget")
local Image=require("widgets/image")
local ImageButton=require("widgets/imagebutton")
local S={}
function S.Panel(width,height,options)
    options=options or {}
    local w=Widget("ai_crafting_panel")
    w.fill=w:AddChild(Image(options.plain and "images/global.xml" or "images/crafting_menu.xml",
        options.plain and "square.tex" or "backing.tex"))
    w.SetFillColour=function(self,r,g,b)self.fill:SetTint(r,g,b,options.opacity or .97)end
    w:SetFillColour(1,1,1)
    w.left=w:AddChild(Image("images/crafting_menu.xml","side.tex"))
    w.right=w:AddChild(Image("images/crafting_menu.xml","side.tex"))
    w.top=w:AddChild(Image("images/crafting_menu.xml","top.tex"))
    w.bottom=w:AddChild(Image("images/crafting_menu.xml","bottom.tex"))
    for _,part in ipairs({w.fill,w.left,w.right,w.top,w.bottom}) do part:SetClickable(false) end
    w.SetSize=function(self,x,y)
        self.fill:ScaleToSize(x+10,y+18)
        self.left:SetPosition(-x/2-8,1);self.left:ScaleToSize(-26,-(y-20))
        self.right:SetPosition(x/2+8,1);self.right:ScaleToSize(26,y-20)
        self.top:SetPosition(0,y/2+10);self.top:ScaleToSize(x+34,38)
        self.bottom:SetPosition(0,-y/2-8);self.bottom:ScaleToSize(x+34,38)
    end
    w:SetSize(width,height);w:SetClickable(false)
    return w
end
function S.Button(width,height)
    local button=ImageButton("images/global_redux.xml","button_carny_long_normal.tex",
        "button_carny_long_hover.tex","button_carny_long_disabled.tex","button_carny_long_down.tex")
    button:ForceImageSize(width or 190,height or 42)
    button:SetFont(BODYTEXTFONT);button:SetTextColour(.98,.91,.73,1);button:SetTextFocusColour(1,1,.9,1)
    return button
end
return S
