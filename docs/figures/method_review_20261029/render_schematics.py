from pathlib import Path
import xml.etree.ElementTree as ET
import re,math
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parent
for path in root.glob('*.svg'):
 tree=ET.parse(path); doc=tree.getroot(); scale=2
 canvas=Image.new('RGB',(2800,1920),'white'); draw=ImageDraw.Draw(canvas)
 for e in doc:
  tag=e.tag.rsplit('}',1)[-1];a=e.attrib
  if tag=='rect':
   x,y,w,h=[float(a.get(k,0))*scale for k in ['x','y','width','height']]
   draw.rounded_rectangle((x,y,x+w,y+h),radius=float(a.get('rx',0))*scale,fill=a.get('fill','white'),outline=a.get('stroke'),width=2)
  elif tag=='text':
   cls=a.get('class'); size={'title':32,'sub':20,'head':22,'body':20,'small':18}[cls];bold=cls in ['title','head']
   fontpath='/System/Library/Fonts/Supplemental/Arial'+(' Bold' if bold else '')+'.ttf'
   x,y=float(a['x'])*scale,float(a['y'])*scale;t=e.text or ''
   font=ImageFont.truetype(fontpath,size*scale)
   while x+draw.textlength(t,font=font)>1350*scale:
    size-=1;font=ImageFont.truetype(fontpath,size*scale)
   if size!={'title':32,'sub':20,'head':22,'body':20,'small':18}[cls]:e.set('style',f'font-size:{size}px')
   draw.text((x,y),t,font=font,fill='#526477' if cls in ['sub','small'] else '#162b40',anchor='ls')
  elif tag=='path':
   nums=[float(n)*scale for n in re.findall(r'-?\d+(?:\.\d+)?',a['d'])]
   if len(nums)==4:
    x1,y1,x2,y2=nums;draw.line(nums,fill='#526477',width=5);th=math.atan2(y2-y1,x2-x1);l=18;w=8
    draw.polygon([(x2,y2),(x2-l*math.cos(th)+w*math.sin(th),y2-l*math.sin(th)-w*math.cos(th)),(x2-l*math.cos(th)-w*math.sin(th),y2-l*math.sin(th)+w*math.cos(th))],fill='#526477')
 canvas.save(path.with_suffix('.png'))
 ET.register_namespace('','http://www.w3.org/2000/svg');tree.write(path,encoding='unicode')
 print(path.with_suffix('.png'))
