local C=loadstring(game:HttpGet("https://raw.githubusercontent.com/jawolskimanowski-ui/CoffeeIFY-renewed/refs/heads/main/CoffeeIFY.lua"))()

local W=C:CreateWindow("CoffeeIFY",{Theme="Paper"})

local H=W:CreateCategory("HOME","lucide-house")
H:CreateSection("Welcome","CoffeeIFY")
H:CreateParagraph("Paper","Default CoffeeIFY theme. Change themes in Settings.")

local T=W:CreateCategory("TOOLS","lucide-wrench")
T:CreateButton("Notify",function()
W:Notify({Title="CoffeeIFY",Description="Hello!",Duration=3})
end)
T:CreateToggle("Example",false,function(v) print(v) end)
T:CreateSlider("Value",0,100,50,function(v) print(v) end)
T:CreateDropdown("Mode",{"One","Two","Three"},"One",function(v) print(v) end)
T:CreateTextbox("Input",nil,"Type here","Input",function(v) print(v) end)
