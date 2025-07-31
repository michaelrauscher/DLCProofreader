%Michael Rauscher 2025

function DLCProofreader()
badlinthresh = .95;

%toggle whether to show name of point in image on mouseover
% labvis = 'off';
labvis = 'hover';

[configpath,~,~]=fileparts(mfilename('fullpath')); %path of this function so we can load/save config data here
pathsfile = fullfile(configpath,'pathmem.set');
pathconf = [];
if(isfile(pathsfile));load(pathsfile,'-mat');end
if isempty(pathconf)
    pathconf = table([],[],[],[],'VariableNames',{'Path','Lastfile','AutoSave','Network'});
end

netdeffile = fullfile(configpath,'netdefs.set');
defnetset = [];
if(isfile(netdeffile));load(netdeffile,'-mat');end
if isempty(defnetset)
    defnetset = table([],[],'VariableNames',{'Network','Config'});
end
curdir = pwd;
dispnames = "";
filenotes = "";
ftabix = [];
[ftab, networks] = getfiles(curdir);
networks =["All detected networks";networks];
autorestore = false;
netix = 1;
restoreix = 1;
initsel = 1;
if ~isempty(ftab)
    dispnames = ftab.dispname;
    filenotes = ftab.filenote;  
    ftabix = 1:height(ftab);
    defix=find(strcmp(curdir,pathconf.Path));
    if ~isempty(defix)
        searchnet = pathconf.Network(defix);
        netix=find(strcmp(networks,searchnet));
        if isempty(netix)
            netix = 1;
        elseif netix>1
            ftabix = find(strcmp(string(ftab.netname),searchnet));
            dispnames = ftab.dispname(ftabix);
            filenotes = ftab.filenote(ftabix);
        end
        searchfile = pathconf.Lastfile(defix);
        restoreix=find(strcmp(string(ftab.csvname),searchfile));
        if isempty(restoreix)||...
               (netix>1 &&(~strcmp(searchnet,string(ftab.netname(restoreix)))))
            restoreix=1;
        end
        initsel = find(ftabix==restoreix);
        if isempty(initsel)
            initsel = 1;
        end
        autorestore = pathconf.AutoSave(defix);
    end
end
numframes = [];%frames for current file
numdlcpts = [];%number of DLC points in current file
numdlccols = [];%number of columns in csv
xlut = [];%go from point index to x column in data display table
ylut = [];%go from point index to y column in data display table
fileix = [];%current file index
fix = [];%current frame
vr = [];%video reader object of current file
vidaspect = 3/4;%aspect ratio
hyp = [];%hyptenuse of current video (so we can always know we're plotting offscreen)
vllut =[];%lookup table for marker vertical line graphics objects
vltempX = [];%template for vertical line graphics object for current file (XData)
vltempY = [];% " but YData
erec = []; %record of events and the frames they occur in.

%plotting related global variables
skellns = [];
scpts = [];
histpts = [];
roipts = [];
showpts = [];
showlns = [];
showmarks = [];
%plot a line as a patch so we can control alpha post-hoc
lineAlphaFcn = @(ax,x,y,color,alpha,varargin) ...
    patch(ax,'XData',[x(:);nan],...
    'YData',[y(:);nan],...
    'EdgeColor',color,...
    'EdgeAlpha',alpha, ...
    varargin{:});

%uistyles that get used a lot things
redstyle = uistyle('BackgroundColor',[1 0.6 0.6]);
% greenstyle =uistyle('BackgroundColor',[173,255,47]./255);
greenstyle = uistyle('BackgroundColor',[0.6 1 0.6]);
bluestyle =uistyle('BackgroundColor',[173,216,230]./255);
boldstyle = uistyle('FontWeight','bold');

%initialize the /!\ PROGRAM WINDOW /!\
f = uifigure('Position',[0 0 1600 900],...
    'CloseRequestFcn',@closecleanup,...
    'WindowState','maximized',...
    'AutoResizeChildren','off',...
    'KeyPressFcn',@keyshort,...
    'WindowScrollWheelFcn',@buttons,...
    'Name','DLC Proofreader Tool');

%determine what theme we're using to set a few colors
themecol = 'k';
if (isprop(f,'Theme') && isprop(f.Theme,'Name')) && strcmp(f.Theme.Name,'Dark Theme')
    themecol = 'w';
end

%video axis
timg = zeros(480,640);
vidax = uiaxes(f);
hold(vidax,'on');
vidim = imagesc(vidax,timg);
colormap(vidax,'gray');
axis(vidax,'off');
xlim(vidax,[0 size(timg,2)]);
ylim(vidax,[0 size(timg,1)]);
vidax.Toolbar = [];
% vidax.Toolbar = axtoolbar(vidax,{'pan','zoomin','zoomout','restoreview'});
% vidax.Interactions = regionZoomInteraction;
vidax.YDir = "reverse";
vidim.ButtonDownFcn = @buttons;
hcirc = scatter(vidax,nan,nan,125,"red",'LineWidth',1.5,'Tag','SelCirc','ButtonDownFcn',@buttons);
zmbtn = uibutton(f,'state','Text',char(8853),'FontSize',15,'ValueChangedFcn',@zmcb,'Tooltip','Toggle Zoom Control');
pnbtn = uibutton(f,'state','Text',char(10021),'FontSize',15,'ValueChangedFcn',@zmcb,'Tooltip','Toggle Pan Control');
hmbtn = uibutton(f,'push','Text',char(8962),'FontSize',17,'ButtonPushedFcn',@zmcb,'Tooltip','Reset View');

%files list and controls
fpanel = uipanel(f,'Title',curdir,'ButtonDownFcn',@buttons);
flisttab = uitable(fpanel,'Data',table(dispnames,repmat(string,size(dispnames)),filenotes));
flisttab.ColumnEditable = [false false true];
flisttab.ColumnWidth = {'fit','fit','auto'};
flisttab.ColumnName = {'Filename','*','Notes'};
flisttab.DoubleClickedFcn = @buttons;
flisttab.KeyPressFcn = @buttons;
netlabel = uilabel(fpanel,"Text","Network Selection:",'FontWeight','Bold');
netdropdown = uidropdown(fpanel,'Items',networks,'ValueChangedFcn',@buttons,'ValueIndex',netix);
scroll(flisttab,"row",initsel);

prevfilebtn = uibutton(f,'Text',char(9650),'ButtonPushedFcn',@buttons,'FontSize',20);
nextfilebtn = uibutton(f,'Text',char(9660),'ButtonPushedFcn',@buttons,'FontSize',20);
savefilebtn = uibutton(f,'Text','Save File','ButtonPushedFcn',@buttons);
delfilebtn = uibutton(f,'Text','Delete File','ButtonPushedFcn',@buttons);
autosavechk = uicheckbox(f,'Text','Autosave');

%tab group for tabs
tabgp = uitabgroup(f,'Units','pixels',"SelectionChangedFcn",@tabcb);

%tab for big whole-picture plotting axis
plottab = uitab(tabgp,"Title","Plot and Process");
datax = uiaxes(plottab);
hold(datax,'on');
xlabel(datax,'Frame (#)');
ylabel(datax,'Position (px)');
datax.Interactions = [];
datax.Toolbar.Visible = 'off';
datax.ButtonDownFcn = @buttons;
dsld = xline(datax,1,themecol);
dlin = [];
danglin = [];

nanrowbtn = uibutton(plottab,'Text','Mark all not visible','ButtonPushedFcn',@buttons);
interprowbtn = uibutton(plottab,'Text','Interpolate all points','ButtonPushedFcn',@buttons);
revertrowbtn = uibutton(plottab,'Text','Revert all points to CSV','ButtonPushedFcn',@buttons);

selstartbtn = uibutton(plottab,'Text','[','ButtonPushedFcn',@buttons);
selstopbtn = uibutton(plottab,'Text',']','ButtonPushedFcn',@buttons);
selresetbtn = uibutton(plottab,'Text','{}','ButtonPushedFcn',@buttons);

wrap180btn = uibutton(plottab,'Text','Wrap ±180°','ButtonPushedFcn',@buttons);
wrap360btn = uibutton(plottab,'Text','Wrap 0:360°','ButtonPushedFcn',@buttons);

%Tab for spreasheet data view
datatab = uitab(tabgp,"Title","Data Table View");
disptbl = uitable(datatab,'Data',table,'RowName','numbered','Multiselect','on');
disptbl.SelectionChangedFcn = @tblcb;
disptbl.KeyPressFcn = @tblcb;
ctab = [];
dtab = [];
atab = [];

%Tab for point/skeleton/event configuration
skeltab = uitab(tabgp,"Title","Skeleton and Event Markers");

editsel = uibutton(skeltab,"State",'Text','Edit Selected','ValueChangedFcn',@skelcb,'FontSize',15,'BackgroundColor',[173,216,230]./255,'FontColor','k');
fixedsel = uibutton(skeltab,"State",'Text','Fixed Point','ValueChangedFcn',@skelcb,'FontSize',15,'Value',1);
segsel = uibutton(skeltab,"State",'Text','Line Segment','ValueChangedFcn',@skelcb,'FontSize',15,'Value',1);
axissel = uibutton(skeltab,"State",'Text','Axis Line','ValueChangedFcn',@skelcb,'FontSize',15,'Value',1);
skelpanel = uipanel(skeltab);

skelnamelabel = uilabel(skelpanel,'Text','Name:');
skelnameedit = uieditfield(skelpanel,'ValueChangingFcn',@skelcb);
skelcollabel = uilabel(skelpanel,'Text','Color:');
skelcoledit = uiimage(skelpanel,"ImageSource",cat(3,.7,.7,.7),"ImageClickedFcn",@skelcb);
addskelbtn = uibutton(skelpanel,'Text','Update','ButtonPushedFcn',@skelcb);
remskelbtn = uibutton(skelpanel,'Text','Revert Changes','ButtonPushedFcn',@skelcb);

ptslistL = uilistbox(skelpanel,"Items","",'Multiselect','off','DoubleClickedFcn',@buttons,'ValueChangedFcn',@skelcb);
ptslistR = uilistbox(skelpanel,"Items","",'Multiselect','off','DoubleClickedFcn',@buttons,'ValueChangedFcn',@skelcb,'Enable','off');

markpanel = uipanel(skeltab,"Title","Event Marker Definition");
marktab = uitable(markpanel,'Multiselect','off');
etab=table([],[],[],[],'VariableNames',{'Event Name','Color','Symbol','Key'});
marktab.Data=etab;
marktab.CellEditCallback = @markcb;
marktab.SelectionChangedFcn = @markcb;
marktab.DoubleClickedFcn = @markcb;
marktab.KeyPressFcn = @markcb;
marktab.ColumnEditable = [true false false];
addmarkbtn = uibutton(markpanel,'Text','Add Marker','ButtonPushedFcn',@markcb);
remmarkbtn = uibutton(markpanel,'Text','Remove Marker','ButtonPushedFcn',@markcb);
marklns = [];
marknodes = [];
markcol = [];
markshort = {};
marksymb = [];
symbseq ='ox+v^><';

exportconfbtn = uibutton(skeltab,'Text','Export Config','ButtonPushedFcn',@buttons);
importconfbtn = uibutton(skeltab,'Text','Import Config','ButtonPushedFcn',@buttons);
setdefconfbtn = uibutton(skeltab,'Text','Set Default for Network','ButtonPushedFcn',@buttons);
resetnetbtn = uibutton(skeltab,'Text','Reset','ButtonPushedFcn',@buttons,'Enable','off');

%video playback controls
playpause = uibutton(f,'Text',char(9205),'ButtonPushedFcn',@buttons,'FontSize',20);
stopbtn = uibutton(f,'Text',char(9209),'ButtonPushedFcn',@buttons,'FontSize',15);
nextframebtn = uibutton(f,'Text','>','ButtonPushedFcn',@buttons);
prevframebtn = uibutton(f,'Text','<','ButtonPushedFcn',@buttons);
spdbtn = uibutton(f,'Text','1x','ButtonPushedFcn',@buttons);
framewind = uieditfield(f,'Enable','off','HorizontalAlignment','center');
stretchlimchk = uicheckbox(f,'Text','Stretch Contrast','Value',true,'ValueChangedFcn',@buttons);

vtimer = timer('ExecutionMode','fixedRate',...
    'TimerFcn',@timercb,'Period',.1,'UserData',1);
progax = uiaxes(f);
hold(progax,'on');
box(progax,'on');
xticks(progax,[]);
yticks(progax,[]);
xlim(progax,[0 1]);
ylim(progax,[0 1]);
progsld = xline(progax,0,themecol,'LineWidth',3);
progax.Toolbar = [];
progax.Color = 'none';
progax.Interactions = [];
progax.ButtonDownFcn = @buttons;

%checkbox tree controls what's plotted
ptstree = uitree(f,'Checkbox','CheckedNodesChangedFcn',@nodecb,'SelectionChangedFcn',@nodecb,'DoubleClickedFcn',@buttons);
boldwithIco = boldstyle;
if themecol == 'w'
    ico = ones(16);
else
    ico = zeros(16);
end
for iii = 1:16
    ico(iii,iii:16)=nan;
end
ico = cat(3,ico,ico,ico);
boldwithIco.Icon = ico;
dlcroot = uitreenode(ptstree,"Text","DLC Points",'Tag',"Root");
addStyle(ptstree,boldwithIco,"node",dlcroot)
fxdroot = uitreenode(ptstree,"Text","Fixed Points",'Tag',"Root");
addStyle(ptstree,boldwithIco,"node",fxdroot)
segroot = uitreenode(ptstree,"Text","Lines and Angles",'Tag',"Root");
addStyle(ptstree,boldwithIco,"node",segroot)
eventroot = uitreenode(ptstree,"Text","Events and Markers",'Tag',"Root");
addStyle(ptstree,boldwithIco,"node",eventroot)

ptnodes = [];
lnnodes = [];

histviewbtn = uibutton(f,'Text','History: All Selected Points','ButtonPushedFcn',@buttons);
histviewbtn.UserData = {'History: None','History: Current Point Only','History: All Selected Points',3};

nanbtn = uibutton(f,'Text','Not Visible','ButtonPushedFcn',@buttons);
interpbtn = uibutton(f,'Text','Interpolate','ButtonPushedFcn',@buttons);
revertbtn = uibutton(f,'Text','Revert to CSV','ButtonPushedFcn',@buttons);

zoomax = uiaxes(f,'Tag','Position');
hold(zoomax,'on');
xlabel(zoomax,'Frame (#)');
ylabel(zoomax,'Position (px)');
zoomax.Interactions = [];
zoomax.Toolbar.Visible = 'off';
zoomax.ButtonDownFcn = @buttons;
zmsld = xline(zoomax,1,themecol);
zmlin = [];
zanglin = [];
zmwind = uispinner(f,'Value',50,'Limits',[3 inf],'RoundFractionalValues','on',...
    'ValueChangedFcn',@buttons,'ValueDisplayFormat','%i Frame Window');

yyaxis(zoomax,'right');
goodbadlns=plot(zoomax,nan,nan,':','Color',[100 212 19]./255);%good (manually corrected)
goodbadlns=[goodbadlns; plot(zoomax,nan,nan,':','Color',[1 0.6 0.6])];%bad (likelihood<badlinthresh)
ylim(zoomax,[0 1]);
zselrgn = area(zoomax,[nan nan],[1 1],'FaceColor',themecol,'FaceAlpha',.3,'EdgeColor','none','ButtonDownFcn',@buttons);

yyaxis(datax,'right');
goodbadlns=[goodbadlns; plot(datax,nan,nan,':','Color',[100 212 19]./255)];%good (manually corrected)
goodbadlns=[goodbadlns; plot(datax,nan,nan,':','Color',[1 0.6 0.6])];%bad (likelihood<badlinthresh)
ylim(datax,[0 1]);
dselrgn = area(datax,[nan nan],[1 1],'FaceColor',themecol,'FaceAlpha',.3,'EdgeColor','none','ButtonDownFcn',@buttons);

goodbadrgn=area(zoomax,0,nan,'FaceColor',[100 212 19]./255,'FaceAlpha',.3,'EdgeColor','none','ButtonDownFcn',@buttons);%good (manually corrected)
goodbadrgn=[goodbadrgn; area(zoomax,0,nan,'FaceColor',[1 .6 .6],'FaceAlpha',.3,'EdgeColor','none','ButtonDownFcn',@buttons)];%bad (likelihood<badlinthresh)
goodbadrgn=[goodbadrgn; area(datax,0,nan,'FaceColor',[100 212 19]./255,'FaceAlpha',.3,'EdgeColor','none','ButtonDownFcn',@buttons)];%good (manually corrected)
goodbadrgn=[goodbadrgn; area(datax,0,nan,'FaceColor',[1 .6 .6],'FaceAlpha',.3,'EdgeColor','none','ButtonDownFcn',@buttons)];%bad (likelihood<badlinthresh)

yyaxis(zoomax,'left');
yyaxis(datax,'left');
zoomax.YAxis(1).Color = themecol;
zoomax.YAxis(2).Color = 'none';
datax.YAxis(1).Color = themecol;
datax.YAxis(2).Color = 'none';

set([goodbadlns;goodbadrgn],'ButtonDownFcn',@buttons,'HitTest','off');
slds = [progsld zmsld dsld];
loadpanel = uipanel(f,'Title','Loading...','Visible','on','Position',[0 0 2000 1100]);
resize(f);
f.SizeChangedFcn = @resize;
drawnow
if ~isempty(ftab);loadvid(restoreix);end
autosavechk.Value = autorestore;%set this after a first file load so we don't try to autosave nothing
    
    function resize(h,~)
        drawnow
        wt = h.Position(3);
        ht = h.Position(4);
        if vidaspect == 1
            vidwt = ht*2/3;
            vidht = vidwt; 
        else
            vidwt = wt/2;
            if vidwt < 750
                vidwt = wt-750;
            end
            vidht = vidaspect * vidwt;
        end
        vidax.InnerPosition = [0 ht-vidht-25 vidwt vidht];
        fpanel.OuterPosition = [0 0 vidwt-100 ht-vidht-25];
        zmbtn.Position = [0 ht-25 25 25];
        pnbtn.Position = [25 ht-25 25 25];
        hmbtn.Position = [50 ht-25 25 25];
        drawnow
        flisttab.OuterPosition = [0 0 fpanel.InnerPosition(3) fpanel.InnerPosition(4)-20];
        netdropdown.Position=[120 flisttab.OuterPosition(4:-1:3)-[0 120] 20];
        netlabel.Position =[5 flisttab.OuterPosition(4) 115 20];

        tht = (flisttab.OuterPosition(4)+20)/4;
        prevfilebtn.Position = [fpanel.OuterPosition(3)+1 fpanel.InnerPosition(4)-tht 99 tht];
        nextfilebtn.Position = [fpanel.OuterPosition(3)+1 fpanel.InnerPosition(4)-2*tht 99 tht];
        savefilebtn.Position = [fpanel.OuterPosition(3)+1 fpanel.InnerPosition(4)-3*tht 99 tht];
        delfilebtn.Position = [fpanel.OuterPosition(3)+1 fpanel.InnerPosition(4)-4*tht 99 tht];
        autosavechk.Position = [fpanel.OuterPosition(3)+7 prevfilebtn.Position(2)+tht 80 20];
                
        playpause.Position = [vidwt+1 ht-50 49 50];
        stopbtn.Position = [vidwt+51 ht-25 49 25];drawnow

        spdbtn.Position = stopbtn.Position;
        spdbtn.Position(2) = spdbtn.Position(2)-25;
        prevframebtn.Position = stopbtn.Position;
        prevframebtn.Position(1) = prevframebtn.Position(1)+50;
        nextframebtn.Position = spdbtn.Position;
        nextframebtn.Position(1) = nextframebtn.Position(1)+50;
        stretchlimchk.Position = [vidwt+6 ht-75 120 20];

        progax.InnerPosition = [vidwt+152 ht-50 wt-vidwt-152 24];
        framewind.Position = progax.InnerPosition;
        framewind.Position(2) = framewind.Position(2)+25;
       
        ptstree.Position = [vidwt+5 ht*.5 + 35 200 ht*.5-120];drawnow
        histviewbtn.Position = [ptstree.Position(1:3)-[0 25 0] 24];
        
        zoomax.OuterPosition = ptstree.Position;
        zoomax.OuterPosition(1) = ptstree.Position(1)+ptstree.Position(3)+15;
        zoomax.OuterPosition(2) = zoomax.OuterPosition(2)-25;
        zoomax.OuterPosition(3) = wt-zoomax.OuterPosition(1)-15;
        zoomax.OuterPosition(4) = zoomax.OuterPosition(4)+25;
        zp = zoomax.InnerPosition;
        zmwind.Position = [zp(1) zp(2)+zp(4)+5 150 25];

        nanbtn.Position = [zp(1)+zp(3)-310 zp(2)+zp(4)+5 100 25];
        interpbtn.Position = [zp(1)+zp(3)-205 zp(2)+zp(4)+5 100 25];
        revertbtn.Position = [zp(1)+zp(3)-100 zp(2)+zp(4)+5 100 25];        
        
        tabgp.Position = [vidwt 0 wt-vidwt ht*.5];drawnow
        datax.OuterPosition = [5 5 tabgp.InnerPosition(3)-10 tabgp.InnerPosition(4)-40];drawnow
        nanrowbtn.Position = [5 datax.OuterPosition(4)+10 150 25];
        interprowbtn.Position = nanrowbtn.Position + [155 0 0 0];
        revertrowbtn.Position = interprowbtn.Position + [155 0 0 0];

        selstartbtn.Position = revertrowbtn.Position + [165 0 -130 0];
        selstopbtn.Position = selstartbtn.Position + [25 0 0 0];
        selresetbtn.Position = selstopbtn.Position + [25 0 0 0];

        wrap180btn.Position = [datax.OuterPosition(1)+datax.OuterPosition(3)-205 datax.OuterPosition(4)+10 100 25];
        wrap360btn.Position = wrap180btn.Position+[105 0 0 0];        

        disptbl.Position = [0 0 tabgp.InnerPosition(3) tabgp.InnerPosition(4)];
        
        skelpanel.OuterPosition = [0 0 600 tabgp.InnerPosition(4)-40];drawnow

        tht = skelpanel.OuterPosition(4)-5;
        twd = skelpanel.OuterPosition(3)/4;
        axissel.Position = [twd*3 tht twd 45];
        segsel.Position = [twd*2 tht twd 45];
        fixedsel.Position = [twd tht twd 45];
        editsel.Position = [0 tht twd 45];

        tht = skelpanel.InnerPosition(4);
        twd = skelpanel.InnerPosition(3);
        ptslistL.Position = [15 15 200 tht-35];
        ptslistR.Position = ptslistL.Position;
        ptslistR.Position(1) = twd-215;
        addskelbtn.Position = [225 75 145 50];
        remskelbtn.Position = [225 25 145 50];

        skelnamelabel.Position = [225 tht-50 145 25];
        skelnameedit.Position = skelnamelabel.Position-[0 25 0 0];
        skelcollabel.Position = skelnameedit.Position-[0 35 0 0];        
        skelcoledit.Position =  [225 skelnameedit.Position(2)-180 145 145];

        markpanel.Position = [602 80 tabgp.InnerPosition(3:4)-[602 80]];drawnow
        marktab.Position = [0 0 markpanel.InnerPosition(3) markpanel.InnerPosition(4)-25];
        mwd = markpanel.InnerPosition(3);
        marktab.ColumnWidth = 'auto';
        marktab.ColumnWidth = {'auto','fit','fit'};
        drawnow
        addmarkbtn.Position =[0 tabgp.InnerPosition(4)-126 mwd/2 25];
        remmarkbtn.Position = [mwd/2 tabgp.InnerPosition(4)-126 mwd/2 25];

        % mwd = markpanel.Position(3);
        importconfbtn.Position = [602 40 mwd/2 40];
        exportconfbtn.Position = [602+mwd/2 40 mwd/2 40];
        setdefconfbtn.Position = [602 0 mwd-50 40];
        resetnetbtn.Position = [602+mwd-50 0 50 40];        

        loadpanel.Position = [vidwt 0 wt-vidwt ht];
    end

    function closecleanup(~,~)
        if isRunning
            stopfcn(1)
            pause(.5);
            closecleanup([],[])
            return
        end
        try
            updatedefaults;
            save(pathsfile,'pathconf','-mat');
            if autosavechk.Value;savefile;end
        catch
            warning('Error saving default values')
        end
        delete(f);
    end

    function timercb(h,~)
        setframe(fix+h.UserData);
    end

    function val= isRunning()
        val = strcmp(vtimer.Running,'on');
    end

    function updatedefaults
        foldix = find(strcmp(curdir,pathconf.Path));
        fname = ftab.csvname(fileix);
        asv = autosavechk.Value;
        net = netdropdown.Value;
        if ~isempty(foldix)
            pathconf.Path(foldix)=string(curdir);
            pathconf.Lastfile(foldix)=string(fname);
            pathconf.AutoSave(foldix)=asv;
            pathconf.Network(foldix)=string(net);
        else
            pathconf = [pathconf; table(string(curdir),string(fname),asv,string(net),...
                'VariableNames',pathconf.Properties.VariableNames)];
        end
    end

    function savefile()
        DLCProof = struct;
        DLCProof.CSVFilename = ftab.csvname(fileix);
        DLCProof.VideoFileName = ftab.vidname(fileix);
        DLCProof.ProofreadCSV = dtab;
        DLCProof.OriginalCSV = ctab;
        
        updatetablines;%recompute from current xy pts to prevent any shenanigans
        DLCProof.SkelAngles = atab;
        trec = erec;
        if ~isempty(erec)
            trec = rmfield(trec,{'Col','Symbol','ShortcutKey','Visible'});
        end
        DLCProof.Events = trec;
        DLCProof.FrameNotes = disptbl.Data.Notes;
        DLCProof.FileNote = flisttab.Data{ftabix==fileix,3};        
        DLCProof.Configuration = exportconfig;
        DLCProof.UISettings.curframe = fix;
        DLCProof.UISettings.showhist = histviewbtn.UserData;
        DLCProof.UISettings.frameskip = vtimer.UserData;
        DLCProof.UISettings.stretchhist = stretchlimchk.Value;
        DLCProof.UISettings.windsize = zmwind.Value;
        DLCProof.UISettings.XLim = vidax.XLim;
        DLCProof.UISettings.YLim = vidax.YLim;
        fname = ftab.savename(fileix);
        save(fname,'DLCProof');
        ftab.isSave(fileix)=true;
        refreshfilesavelabels;
    end

    function conf = exportconfig()
        conf = struct;
        conf.Network = ftab.netname(fileix);
        %replace graphics handles with label of point handle so we
        %can reassign it when we recreate it upon loading
        skellist = ptslistL.ItemsData;
        tdlc = [];
        tfxd = [];
        tskl = [];
        for i = 1:length(skellist)
            tt=skellist(i);            
            switch tt.Tag
                case {"DLC","Fixed"}
                    ix = find(strcmp({roipts.Label},tt.name));
                    tt.Visible = showpts(ix);

                    %initialize reversion color to what's saved next time we load
                    tt = rmfield(tt,'origcolor');

                    if strcmp(tt.Tag,"DLC")
                        tdlc = [tdlc; tt];
                    else
                        %name at creation only matters for DLC points to
                        %make sure they line up with DLC CSV
                        tt = rmfield(tt,'csvname');                        
                        tt.Position = roipts(ix).Position;
                        tfxd = [tfxd; tt];
                    end
                case {"Segment","Axis"}
                    ix=strcmp(tt.name,{skellns.Tag});
                    udat=skellns(ix).UserData;
                    tt = rmfield(tt,{'origcolor','csvname'});
                    udat.origin.Label;
                    tt.OriginPoint = udat.origin.Label;
                    tt.TerminusPoint = udat.terminus.Label;
                    tt.Wrap = udat.wrap;
                    tt.Visible = showlns(ix);
                    tskl = [tskl; tt];
            end
        end
        conf.DLCPoints = tdlc;
        conf.FixedPoints = tfxd;
        conf.Skeleton = tskl;
        trec = erec;
        %this goes in the main part of the save
        if ~isempty(trec)
            trec = rmfield(trec,'FrameIndex');
        end
        conf.EventsConfiguration = trec;
    end

    function importconfig(conf)
        checked = [];
        if ~strcmp(ftab.netname(fileix),conf.Network)
            sel = 'Cancel';
            while ~any(strcmp(sel,{'Yes','No'}))
            sel = questdlg(['Network name for this configuration file...' ...
                ' does not match current network. Try loading anyway?'],...
                'Network mismatch','Cancel');
            end
            if strcmp(sel,'No');return;end
        end
        dlc = conf.DLCPoints;
        for i = 1:length(dlc)
            ldat = dlc(i);
            col = ldat.color;
            ptnodes(i).UserData=col;
            roipts(i).Color = col;
            histpts(i).MarkerEdgeColor = col;
            zmlin(i,1).EdgeColor = col;
            zmlin(i,2).EdgeColor = col;
            dlin(i,1).EdgeColor = col;
            dlin(i,2).EdgeColor = col;
            scpts.CData(i,:)=col;

            if ldat.Visible==1
                vis = 'on';
                checked = [checked; ptnodes(i)];
            else
                vis = 'off';
            end
        end
        fxd = conf.FixedPoints;
        for i = 1:length(fxd)
            ldat = fxd(i);      
            items = ptslistL.ItemsData;
            ix = find(strcmp([items.name],'Lines and Angles')&strcmp([items.Tag],'Root'));
            dat = items(ix);
            dat.name = ldat.name;
            dat.csvname = dat.name;
            dat.color = ldat.color;
            dat.origcolor = dat.color;
            dat.Tag = 'Fixed';
            items = [items(1:ix-1) dat items(ix:end)];
            lst = ptslistL.Items;
            lst = [lst(1:ix-1) {char(dat.name)} lst(ix:end)];
            ptslistL.ItemsData = items;
            ptslistL.Items = lst;
            ptslistL.ValueIndex = ix;

            ptslistR.ItemsData = items;
            ptslistR.Items = lst;

            ptnodes = [ptnodes; uitreenode(fxdroot,'Text',dat.name,'NodeData',length(ptnodes)+1,'Tag',"Fixed",'UserData',dat.color)];
            expand(fxdroot);

            pos = ldat.Position;
            udat = struct;
            udat.ix = length(roipts)+1;
            udat.memberlines = [];
            udat.memberlineix = [];
            udat.memberlinetype = [];
            udat.memberlinepartner = [];
            roipts = [roipts; images.roi.Point(vidax,'Position',pos,...
                'Color',dat.color,'Label',dat.name,'ContextMenu',[],...
                'Deletable',false,'LabelVisible',labvis,'UserData',...
                udat)];
            addlistener(roipts(end),'ROIClicked',@ptcb);
            addlistener(roipts(end),'MovingROI',@ptcb);
            addlistener(roipts(end),'ROIMoved',@ptcb);
            if ldat.Visible==1
                checked = [checked; ptnodes(end)];
            else
                roipts(end).Visible = 'off';
            end      
        end
        seg = conf.Skeleton;
        for i = 1:length(seg)
            ldat = seg(i);
            ltag = ldat.Tag;
            if strcmp(ltag,'Segment')
                lstyle = '-';
                ltype = 0;
            else
                lstyle = '--';
                ltype = 1;
            end
            oname = ldat.OriginPoint;            
            oix = find(strcmp(oname,{roipts.Label}));
            tname = ldat.TerminusPoint;            
            tix = find(strcmp(tname,{roipts.Label}));

            items = ptslistL.ItemsData;
            dat = struct;
            dat.name = ldat.name;
            dat.csvname = dat.name;
            dat.color = ldat.color;
            dat.origcolor = dat.color;
            dat.Tag = ltag;
            items = [items dat];
            lst = ptslistL.Items;
            lst = [lst {char(dat.name)}];
            ptslistL.ItemsData = items;
            ptslistL.Items = lst;
            ptslistR.ItemsData = items;
            ptslistR.Items = lst;

            lnnodes = [lnnodes; uitreenode(segroot,'Text',dat.name,'NodeData',length(lnnodes)+1,'Tag',ltag,'UserData',dat.color)];
            expand(segroot);
            if ldat.Visible==1
                checked = [checked; lnnodes(end)];
                vis = 'on';
            else
                vis = 'off';
            end

            udat = struct;
            udat.name = dat.name;
            udat.origin = roipts(oix);
            udat.terminus = roipts(tix);
            udat.dispnode = lnnodes(end);
            if isfield(ldat,'Wrap')
                udat.wrap = ldat.Wrap;
            else
                udat.wrap = 360;
            end
            skellns = [skellns plot(vidax,[nan,nan],[nan,nan],'Color',dat.color,...
                'Tag',dat.name,'UserData',udat,'LineStyle',lstyle,'Visible',vis)];
            restackhandles();

            roipts(oix).UserData.memberlines = [roipts(oix).UserData.memberlines skellns(end)];
            roipts(oix).UserData.memberlineix(end+1)=1;
            roipts(oix).UserData.memberlinetype(end+1)=ltype;
            roipts(oix).UserData.memberlinepartner = [roipts(oix).UserData.memberlinepartner roipts(tix)];

            roipts(tix).UserData.memberlines = [roipts(tix).UserData.memberlines skellns(end)];
            roipts(tix).UserData.memberlineix(end+1)=2;
            roipts(tix).UserData.memberlinetype(end+1)=ltype;
            roipts(tix).UserData.memberlinepartner = [roipts(tix).UserData.memberlinepartner roipts(oix)];
        
            if oix>numdlcpts
                odat = repmat(roipts(oix).Position,numframes,1);
            else
                odat = [dtab{:,[oix*3-2 oix*3-1]}];
            end
            if tix>numdlcpts
                tdat = repmat(roipts(tix).Position,numframes,1);
            else
                tdat = [dtab{:,[tix*3-2 tix*3-1]}];
            end
            ang = atan2d(tdat(:,2)-odat(:,2),tdat(:,1)-odat(:,1));
            if udat.wrap==360
                ang = wrapTo360(ang);
            end            
            yyaxis(datax,'left');
            yyaxis(zoomax,'left');
            zanglin = [zanglin; lineAlphaFcn(zoomax,1:numframes,ang,dat.color,.2,'ButtonDownFcn',@buttons,'Visible',vis,'Tag',dat.name)];
            danglin = [danglin; lineAlphaFcn(datax,1:numframes,ang,dat.color,.1,'ButtonDownFcn',@buttons,'Visible',vis,'Tag',dat.name)];
            atab = [atab table(ang,'VariableNames',{char(dat.name)})];
        end
        evt = conf.EventsConfiguration;
        for i = 1:length(evt)
            
            ldat = evt(i);

            defname = ldat.Name;
            defcol = ldat.Col;
            defsymb = ldat.Symbol;
            defshort = ldat.ShortcutKey;
            
            tts = struct;
            tts.Name = defname;
            tts.Col = defcol;
            tts.Symbol = defsymb;
            tts.ShortcutKey = defshort;
            tts.FrameIndex = [];
            tts.Visible = ldat.Visible;
            erec = [erec;tts];

            marknodes = [marknodes uitreenode(eventroot,'Text',defname,'Tag',"Event",'UserData',defcol)];
            expand(eventroot);
            if tts.Visible==1
                checked = [checked; marknodes(end)];
                vis = 'on';
            else
                vis = 'off';
            end

            markcol =[markcol; defcol];
            markshort = [markshort {defshort}];
            marksymb = [marksymb defsymb];
            marktab.Data = [marktab.Data;...
                table(defname," ",string(defsymb),string(defshort),...
                'VariableNames',{'Event Name','Color','Symbol','Key'})];
            s = uistyle('BackgroundColor',defcol);

            addStyle(marktab,s,"cell",[height(marktab.Data) 2]);

            yyaxis(zoomax,'right');
            yyaxis(datax,'right');
            tlin = plot(zoomax,vltempX,vltempY,'--','Color',defcol,'Visible',vis);
            tlin = [tlin plot(datax,vltempX,vltempY,'--','Color',defcol,'Visible',vis)];
            tlin = [tlin plot(zoomax,1:numframes,nan(1,numframes),defsymb,'Color',defcol,'Visible',vis)];
            tlin = [tlin plot(datax,1:numframes,nan(1,numframes),defsymb,'Color',defcol,'Visible',vis)];
            tlin = [tlin area(zoomax,1:numframes,nan(1,numframes),'EdgeColor','none','FaceColor',defcol,'FaceAlpha',.1)];
            tlin = [tlin area(datax,1:numframes,nan(1,numframes),'EdgeColor','none','FaceColor',defcol,'FaceAlpha',.1)];
            marklns =[marklns;tlin];
            yyaxis(zoomax,'left');
            yyaxis(datax,'left');            
        end
        set(marklns,'HitTest','off');
        ptstree.CheckedNodes = [];
        ptstree.CheckedNodes = checked;
        marktab.ColumnWidth = 'auto';
        marktab.ColumnWidth = {'auto','fit','fit','fit'};
    end

    function deletefile()
        fname = ftab.savename(fileix);
        delete(fname);
        ftab.isSave(fileix)=false;
        refreshfilesavelabels;
    end

    function markframe(idx,frix)
        if nargin<2
            frix = fix;
        end
        frix = frix(:)';
        for ix = idx(:)'
            mark = false(1,numframes);
            markdf = mark;
            markix = erec(ix).FrameIndex;
            val = ismember(frix,markix);
            if all(val)
                markix(ismember(markix,frix))=[];
            else
                markix = sort([markix frix(~val)]);
            end
            erec(ix).FrameIndex = markix;
            marklns(ix,3).YData=double(mark);
            marklns(ix,4).YData=double(mark);
            mark(markix)=true;

            marklns(ix,5).YData(mark)=1;
            marklns(ix,6).YData(mark)=1;
            marklns(ix,5).YData(~mark)=nan;
            marklns(ix,6).YData(~mark)=nan;

            val = diff([false;mark(:)]);
            markdf(val==1)=true;
            markdf(val(2:end)==-1)=true;
            marklns(ix,1).YData(vllut(markdf))=1;
            marklns(ix,2).YData(vllut(markdf))=1;
            marklns(ix,1).YData(vllut(~markdf))=nan;
            marklns(ix,2).YData(vllut(~markdf))=nan;
            marklns(ix,3).YData(val(2:end)==-1)=0;
            marklns(ix,4).YData(val(2:end)==-1)=0;
            marklns(ix,3).YData(val==1)=1;
            marklns(ix,4).YData(val==1)=1;
            marklns(ix,3).YData(~markdf)=nan;
            marklns(ix,4).YData(~markdf)=nan;
        end
        if tabgp.SelectedTab==datatab
            tabcb(tabgp,[])
        end
    end

    % function omarkframe(ix,frix)
    %     if nargin<2
    %         frix = fix;
    %     end
    %     if length(frix)>1
    %         markix = erec(ix).FrameIndex;
    %         val = ismember(frix,markix);
    %         if all(val)
    %             markix(markix==frix)=[];
    %         else
    %             markix = sort([markix frix(~val)]);
    %         end
    % 
    %         return
    %     end
    %     if ismember(frix,erec(ix).FrameIndex)
    %         % marklns(ix,1).YData(vllut(frix))=nan;
    %         % marklns(ix,2).YData(vllut(frix))=nan;
    %         % marklns(ix,3).YData(frix)=nan;
    %         % marklns(ix,4).YData(frix)=nan;
    %         marklns(ix,5).YData(frix)=nan;
    %         marklns(ix,6).YData(frix)=nan;
    %         erec(ix).FrameIndex(erec(ix).FrameIndex==frix)=[];
    %         label = false;
    %     else
    %         % marklns(ix,1).YData(vllut(frix))=1;
    %         % marklns(ix,2).YData(vllut(frix))=1;
    %         % marklns(ix,3).YData(frix)=1;
    %         % marklns(ix,4).YData(frix)=1;
    %         marklns(ix,5).YData(frix)=1;
    %         marklns(ix,6).YData(frix)=1;
    %         erec(ix).FrameIndex(end+1)=frix;
    %         label = true;
    %     end
    %     val = ~isnan(marklns(ix,6).YData);
    %     val = diff([false;val(:)]);
    %     mark = false(size(val));
    %     marklns(ix,3).YData=double(mark);
    %     marklns(ix,4).YData=double(mark);
    %     mark(val==1)=true;
    %     mark(val(2:end)==-1)=true;
    %     marklns(ix,1).YData(vllut(mark))=1;
    %     marklns(ix,2).YData(vllut(mark))=1;
    %     marklns(ix,1).YData(vllut(~mark))=nan;
    %     marklns(ix,2).YData(vllut(~mark))=nan;
    %     marklns(ix,3).YData(val(2:end)==-1)=0;
    %     marklns(ix,4).YData(val(2:end)==-1)=0;
    %     marklns(ix,3).YData(val==1)=1;
    %     marklns(ix,4).YData(val==1)=1;
    %     marklns(ix,3).YData(~mark)=nan;
    %     marklns(ix,4).YData(~mark)=nan;        
    % 
    %     erec(ix).FrameIndex = sort(erec(ix).FrameIndex);
    %     if showmarks(ix)
    %         cix=find(strcmp(erec(ix).Name,disptbl.Data.Properties.VariableNames));
    %         ptstree.SelectedNodes=marknodes(ix);
    % 
    %         if tabgp.SelectedTab~=datatab;return;end
    %         scroll(disptbl,"column",cix);
    %         if label
    %             s = uistyle('BackgroundColor',erec(ix).Col);
    %             addStyle(disptbl,s,"cell",[frix cix]);
    %         else
    %             st = disptbl.StyleConfigurations.TargetIndex;
    %             iix =[];
    %             for i = 1:length(st)
    %                 if all(size(st{i})==[1 2])&&all(st{i}==[frix cix])
    %                     iix(end+1)=i;
    %                 end
    %             end
    %             if isempty(iix);return;end
    %             removeStyle(disptbl,iix);
    %         end
    %     end
    % end

    function markcb(h,e)
        switch h
            case addmarkbtn
                ix= height(marktab.Data)+1;
                defname = "Event " + string(ix);
                ctr = 0;
                if ~isempty(erec)
                    while (any(strcmp([erec.Name],defname)))
                        ctr = ctr+1;
                        defname = "Event " + string(ix+ctr);
                    end
                end
                defcol = lines(ix+ctr);
                defcol = defcol(end,:);
                six = mod(ix+ctr,7);
                if six==0;six=7;end
                if ix<10
                    defshort = char(num2str(ix));
                else
                    defshort = char(87+ix);
                end

                tts = struct;
                tts.Name = defname;
                tts.Col = defcol;
                tts.Symbol = symbseq(six);
                tts.ShortcutKey = defshort;
                tts.FrameIndex = [];
                tts.Visible = true;
                erec = [erec;tts];

                markcol =[markcol; defcol];
                markshort = [markshort {defshort}];
                marksymb = [marksymb symbseq(six)];
                marktab.Data = [marktab.Data;...
                    table(defname," ",string(symbseq(six)),string(defshort),...
                    'VariableNames',{'Event Name','Color','Symbol','Key'})];
                s = uistyle('BackgroundColor',defcol);
                addStyle(marktab,s,"cell",[ix 2]);
                marktab.ColumnWidth = 'auto';
                marktab.ColumnWidth = {'auto','fit','fit','fit'};
                yyaxis(zoomax,'right');
                yyaxis(datax,'right');
                tlin = plot(zoomax,vltempX,vltempY,'--','Color',defcol);
                tlin = [tlin plot(datax,vltempX,vltempY,'--','Color',defcol)];
                tlin = [tlin plot(zoomax,1:numframes,nan(1,numframes),symbseq(six),'Color',defcol)];
                tlin = [tlin plot(datax,1:numframes,nan(1,numframes),symbseq(six),'Color',defcol)];
                tlin = [tlin area(zoomax,1:numframes,nan(1,numframes),'EdgeColor','none','FaceColor',defcol,'FaceAlpha',.1)];
                tlin = [tlin area(datax,1:numframes,nan(1,numframes),'EdgeColor','none','FaceColor',defcol,'FaceAlpha',.1)];
                marklns =[marklns;tlin];
                set(marklns,'HitTest','off');
                yyaxis(zoomax,'left');
                yyaxis(datax,'left');
                marknodes = [marknodes uitreenode(eventroot,'Text',defname,'Tag',"Event",'UserData',defcol)];
                expand(eventroot);
                refreshpts;
                n = struct;
                n.EventName='CheckedNodesChanged';
                nodecb(ptstree,n);
            case remmarkbtn
                ix = marktab.Selection;
                if isempty(ix);return;end
                ix = ix(1);
                marktab.Data(ix,:)=[];
                erec(ix)=[];
                delete(marklns(ix,:));
                marklns(ix,:)=[];
                markcol(ix,:)=[];
                marksymb(ix)=[];
                markshort(ix)=[];
                delete(marknodes(ix));
                marknodes(ix)=[];
                refreshpts;
                n = struct;
                n.EventName='CheckedNodesChanged';
                nodecb(ptstree,n);
                for i=1:length(erec)
                    s = uistyle('BackgroundColor',markcol(i,:));
                    addStyle(marktab,s,"cell",[i 2]);
                end
            case marktab                
                switch e.EventName
                    case 'KeyPress'
                        c = h.Selection;
                        if isempty(c) || c(2)~=4;return;end                        
                        ix=c(1);      
                        c =c(2);
                        val = e.Character;
                        if ~isstrprop(val,'alphanum');return;end
                        if any(contains(markshort,val));return;end
                        % if any(strfind(markshort,val));return;end
                        markshort{ix}=val;
                        marktab.Data{ix,c} = string(val);                                              
                    case 'DoubleClicked'
                        c = h.Selection;
                        if isempty(c) || c(2)~=2;return;end
                        ix=c(1);
                        newcol = uisetcolor(markcol(ix,:),'Select Event Marker Color');
                        focus(f);
                        if all(newcol==markcol(ix,:));return;end
                        markcol(ix,:)=newcol;
                        s = uistyle('BackgroundColor',newcol);
                        addStyle(marktab,s,"cell",[ix 2]);
                        erec(ix).Col = newcol;
                        set(marklns(ix,1:4),'Color',newcol);
                        set(marklns(ix,5:6),'FaceColor',newcol);
                        marknodes(ix).UserData = newcol;
                        refreshpts;
                    case 'CellEdit'
                        if e.Indices(2)~=1;return;end
                        ix = e.Indices(1);
                        val = h.Data{:,1};
                        val(ix)=[];
                        if any(strcmp(val,e.NewData))
                            h.Data{ix,1}=e.PreviousData;
                            return
                        end
                        if showmarks(ix)
                            oldname = erec(ix).Name;
                            tix=find(strcmp(disptbl.Data.Properties.VariableNames,oldname));
                            disptbl.Data.Properties.VariableNames{tix}=char(e.NewData);
                        end
                        erec(ix).Name = e.NewData;
                        marknodes(ix).Text = e.NewData;
                end
                   
        end
    end

    function ptcb(h,e)
        pix = h.UserData.ix;
        if pix<=numdlcpts
            e.EventName;
            switch e.EventName
                case 'ROIClicked'
                    hcirc.Visible='on';
                    selnode = ptstree.SelectedNodes;
                    if any(ismember(selnode,lnnodes))
                        dnodes = {lnnodes(showlns).Text};
                        lnnames = {h.UserData.memberlines.Tag};    
                        lnnames = lnnames(ismember(lnnames,dnodes));
                        if isempty(lnnames)%not a member of any visible lines, go to point
                            setnode(ptnodes(pix));
                        elseif ~any(strcmp(selnode.Text,lnnames))
                            setnode(lnnodes(strcmp(lnnames{1},{lnnodes.Text})))
                        end
                    else
                        setnode(ptnodes(pix));
                        revertbtn.Enable = 'on';
                    end
                    if tabgp.SelectedTab == datatab
                        addStyle(disptbl,greenstyle,"cell",[[fix;fix] [xlut(pix); ylut(pix)]])
                    end
                case {'MovingROI','ROIMoved'} %pointer moving or stopped
                    %get position of pointer
                    val = h.Position;
                    hcirc.XData = val(1);
                    hcirc.YData =val(2);
                    zmlin(pix,1).YData(fix)=val(1);
                    zmlin(pix,2).YData(fix)=val(2);
                    switch tabgp.SelectedTab
                        case datatab
                            %update values in data display table if it's open
                            disptbl.Data{fix,[xlut(pix) ylut(pix)]}=val;
                        case plottab
                            %update lines in plot tab if it's open (otherwise will
                            %update when selected)
                            dlin(pix,1).YData(fix)=val(1);
                            dlin(pix,2).YData(fix)=val(2);
                    end
                    if strcmp(e.EventName,'ROIMoved')
                        %update everything when we're done moving to be sure
                        disptbl.Data{fix,[xlut(pix) ylut(pix)]}=val;
                        dlin(pix,1).YData(fix)=val(1);
                        dlin(pix,2).YData(fix)=val(2);
                        dtab{fix,[pix*3-2 pix*3-1 pix*3]} = [val inf];
                        histpts(pix).XData(fix)=val(1);
                        histpts(pix).YData(fix)=val(2);
                        revertbtn.Enable = 'on';
                        updatehist;
                        % goodbadlns(1).YData(vllut(fix))=1;
                        % goodbadlns(2).YData(vllut(fix))=nan;
                        % goodbadlns(3).YData(vllut(fix))=1;
                        % goodbadlns(4).YData(vllut(fix))=nan;
                        if isempty(ptstree.SelectedNodes)||~any(ptstree.SelectedNodes==ptnodes)
                            hcirc.Visible = 'off';
                        end
                    end
            end
        end
        if ~isRunning() || pix>numdlcpts; updateskellines(pix,true);end
    end

    function prunelines(lns)
        if isempty(lns);return;end
        for L = lns(:)'
            o = L.UserData.origin;
            t = L.UserData.terminus;
            d = L.UserData.dispnode;
            n = L.Tag;
            lnnodes(lnnodes==d)=[];
            delete(d);
            ix=strcmp(ptslistL.Items,n);
            items = ptslistL.ItemsData;
            lst = ptslistL.Items;
            items(ix)=[];
            lst(ix)=[];
            for R = [o t]
                ix = find(R.UserData.memberlines==L);
                R.UserData.memberlines(ix)=[];
                R.UserData.memberlinetype(ix)=[];
                R.UserData.memberlineix(ix) = [];
                R.UserData.memberlinepartner(ix)=[];
            end
            skellns(skellns==L)=[];
            delete(L);
            ptslistL.ItemsData = items;
            ptslistR.ItemsData = items;
            ptslistL.Items = lst;
            ptslistR.Items = lst;
            
            lx = strcmp({zanglin.Tag},n);
            delete(zanglin(lx));
            delete(danglin(lx));
            zanglin(lx)=[];
            danglin(lx)=[];
            atab(:,lx)=[];
        end
        refreshpts;
    end

    function updatetablines()
        for L = skellns(:)'
            oix=find(L.UserData.origin==roipts);
            tix=find(L.UserData.terminus==roipts);
            name = L.Tag;
            if oix>numdlcpts
                odat = repmat(roipts(oix).Position,numframes,1);
            else
                odat = [dtab{:,[oix*3-2 oix*3-1]}];
            end
            if tix>numdlcpts
                tdat = repmat(roipts(tix).Position,numframes,1);
            else
                tdat = [dtab{:,[tix*3-2 tix*3-1]}];
            end            
            ang = atan2d(tdat(:,2)-odat(:,2),tdat(:,1)-odat(:,1));
            if L.UserData.wrap==360
                ang = wrapTo360(ang);
            end
            atab{:,name}= ang;
            if ismember(disptbl.Data.Properties.VariableNames,name)
                disptbl.Data{:,name}=ang;
            end
        end
    end

    function updateskellines(pix,updata)
        if nargin<2;updata=false;end
        if nargin<1;pix = 1:length(roipts);end
        for i = pix(:)'
            nlines = numel(roipts(i).UserData.memberlines);
            if showpts(i) && nlines>0
                if i<=numdlcpts && isRunning
                    pos = [scpts.XData(i) scpts.YData(i)];
                else
                    pos = roipts(i).Position;
                    pos(pos<0)=nan;
                end
                for j = 1:nlines
                    if ~updata&&strcmp(roipts(i).UserData.memberlines(j).Visible,'off');continue;end
                    lix = roipts(i).UserData.memberlineix(j);
                    if roipts(i).UserData.memberlinetype(j)==0 %segment
                        roipts(i).UserData.memberlines(j).XData(lix)=pos(1);
                        roipts(i).UserData.memberlines(j).YData(lix)=pos(2);
                        pos2 = roipts(i).UserData.memberlines(j).XData(lix~=[1 2]);
                        pos2(2)= roipts(i).UserData.memberlines(j).YData(lix~=[1 2]);
                    else %axis
                        lh = roipts(i).UserData.memberlines(j);
                        k = find(roipts==roipts(i).UserData.memberlinepartner(j));
                        if k<=numdlcpts && strcmp(vtimer.Running,'on')
                            pos2 = [scpts.XData(k) scpts.YData(k)];
                        else
                            pos2 = roipts(k).Position;
                            pos2(pos2<0)=nan;
                        end
                    end
                    if roipts(i).UserData.memberlinetype(j)==1 || updata                        
                        if lix == 2
                            theta =atan2d(pos(2)-pos2(2),pos(1)-pos2(1));
                        else
                            theta = atan2d(pos2(2)-pos(2),pos2(1)-pos(1));
                        end
                        if roipts(i).UserData.memberlines(j).UserData.wrap==360
                            theta = wrapTo360(theta);
                        end
                        if roipts(i).UserData.memberlinetype(j)==1
                            lh.XData = [pos(1)+hyp*cosd(theta) pos(1)-hyp*cosd(theta)];
                            lh.YData = [pos(2)+hyp*sind(theta) pos(2)-hyp*sind(theta)];
                        end
                        if updata
                            lnx = roipts(i).UserData.memberlines(j)==skellns;
                            oix=find(skellns(lnx).UserData.origin==roipts);
                            tix=find(skellns(lnx).UserData.terminus==roipts);
                            if any([oix tix]>numdlcpts)
                                if oix>numdlcpts
                                    odat = repmat(roipts(oix).Position,numframes,1);
                                else
                                    odat = [dtab{:,[oix*3-2 oix*3-1]}];
                                end
                                if tix>numdlcpts
                                    tdat = repmat(roipts(tix).Position,numframes,1);
                                else
                                    tdat = [dtab{:,[tix*3-2 tix*3-1]}];
                                end
                                theta = atan2d(tdat(:,2)-odat(:,2),tdat(:,1)-odat(:,1));
                                if roipts(i).UserData.memberlines(j).UserData.wrap==360
                                    theta = wrapTo360(theta);
                                end
                                atab{:,skellns(lnx).Tag}=theta;
                                if showlns(lnx)
                                    disptbl.Data{:,skellns(lnx).Tag}=theta;
                                end
                                zanglin(lnx).YData(1:numframes) = theta;
                                danglin(lnx).YData(1:numframes) = theta;
                            else
                                zanglin(lnx).YData(fix) = theta;
                                danglin(lnx).YData(fix) = theta;
                                if showlns(lnx)
                                    disptbl.Data{fix,skellns(lnx).Tag}=theta;
                                end
                                atab{fix,skellns(lnx).Tag}=theta;
                            end
                        end
                    end
                end
            end
        end
    end

    function updatehist()
        switch histviewbtn.UserData{4}
            case 1 %None
                set(histpts,'Visible','off');
                goodix = false(numframes,1);
                badix = goodix;
            case 2 %Current Selection Only
                set(histpts,'Visible','off');
                goodix = false(numframes,1);
                badix = goodix;
                if ~isempty(ptstree.SelectedNodes)
                    nix = find(ptstree.SelectedNodes==ptnodes, 1);
                    if isempty(nix)
                        nix = find(ptstree.SelectedNodes==lnnodes, 1);
                        if ~isempty(nix)
                            oix=find(skellns(nix).UserData.origin==roipts);
                            tix=find(skellns(nix).UserData.terminus==roipts);

                            if oix<=numdlcpts && showpts(oix)
                                histpts(oix).Visible = 'on';
                                goodix=goodix|dtab{:,oix*3}==inf;
                                badix=badix|dtab{:,oix*3}<badlinthresh;
                            end
                            if tix<=numdlcpts && showpts(oix)
                                histpts(tix).Visible = 'on';
                                goodix=goodix|dtab{:,tix*3}==inf;
                                badix=badix|dtab{:,tix*3}<badlinthresh;
                            end
                        end
                    elseif nix<=numdlcpts && showpts(nix)
                        histpts(nix).Visible = 'on';
                        goodix=goodix|dtab{:,nix*3}==inf;
                        badix=badix|dtab{:,nix*3}<badlinthresh;
                    end
                end
            case 3 %All
                set(histpts(showpts(1:numdlcpts)),'Visible','on');
                set(histpts(~showpts(1:numdlcpts)),'Visible','off');
                goodix=any(dtab{:,find(showpts(1:numdlcpts))*3}==inf,2);
                badix=any(dtab{:,find(showpts(1:numdlcpts))*3}<badlinthresh,2);
        end
        goodbadrgn(1).YData(goodix)=1;
        goodbadrgn(3).YData(goodix)=1;
        goodbadrgn(1).YData(~goodix)=nan;
        goodbadrgn(3).YData(~goodix)=nan;
        goodbadrgn(2).YData(badix)=1;
        goodbadrgn(4).YData(badix)=1;
        goodbadrgn(2).YData(~badix)=nan;
        goodbadrgn(4).YData(~badix)=nan;

        goodix = diff([false goodix(:)']);
        badix = diff([false badix(:)']);

        goodix = goodix==1 | [goodix(2:end) 0] == -1;
        badix = badix==1 | [badix(2:end) 0] == -1;

        goodbadlns(1).YData(vllut(goodix))=1;
        goodbadlns(3).YData(vllut(goodix))=1;
        goodbadlns(1).YData(vllut(~goodix))=nan;
        goodbadlns(3).YData(vllut(~goodix))=nan;
        goodbadlns(2).YData(vllut(badix))=1;
        goodbadlns(4).YData(vllut(badix))=1;
        goodbadlns(2).YData(vllut(~badix))=nan;
        goodbadlns(4).YData(vllut(~badix))=nan;
    end

    function nodecb(h,e)
        showpts = ismember(ptnodes, h.CheckedNodes);
        showdlcpts = showpts(1:numdlcpts);
        showlns = ismember(lnnodes, h.CheckedNodes);
        showmarks = ismember(marknodes,h.CheckedNodes);
        
        nd = h.SelectedNodes;

        if strcmp(e.EventName,'CheckedNodesChanged')
            for i = find(showlns(:)')
                oix = find(skellns(i).UserData.origin==roipts);
                tix = find(skellns(i).UserData.terminus==roipts);
                if ~all(showpts([oix tix]));showlns(i)=0;end
            end
            set(skellns(showlns),'Visible','on');
            set(skellns(~showlns),'Visible','off');

            for i = 1:length(showmarks)
                erec(i).Visible = showmarks(i);
            end
            set(marklns(showmarks,:),'Visible','on');
            set(marklns(~showmarks,:),'Visible','off');
            updateskellines;
            if strcmp(vtimer.running,'off')
                set(roipts(showpts),'Visible','on');
                set(roipts(~showpts),'Visible','off');
            end

            ttab = dtab;
            ttab = [ttab atab(:,showlns)];
            if ~isempty(showmarks)
                for i = 1:length(showmarks)
                    erec(i).Visible = showmarks(i);
                    if showmarks(i)
                        ttab = [ttab table(repmat(string,height(dtab),1),'VariableNames',{char(erec(i).Name)})];
                    end
                end
            end
            ttab = [ttab disptbl.Data(:,end)];
            ttab(:,3:3:numdlccols)=[];
            xlut=1:2:numdlcpts*2;
            ylut=2:2:numdlcpts*2;
            ttab(:,[xlut(~showdlcpts) ylut(~showdlcpts)])=[];
            xlut = double(showdlcpts);
            xlut(showdlcpts)=1:2:sum(showdlcpts)*2;
            ylut = double(showdlcpts);
            ylut(showdlcpts)=2:2:sum(showdlcpts)*2;
            disptbl.Data = ttab;
            disptbl.ColumnWidth = 'auto';
            disptbl.ColumnWidth = [repmat({'fit'},[1 width(ttab)-1]) {'auto'}];
            ed = false(1,width(ttab));
            ed(end)=true;
            disptbl.ColumnEditable = ed;
            if tabgp.SelectedTab==datatab;tabcb(tabgp);end               
        end
        six=[];
        cix=[];
        if ~isempty(nd)&&any(nd==lnnodes)
            zoomax.Tag = 'Angle';
            ylabel(zoomax,'Angle (°)');
            ylabel(datax,'Angle (°)');
            set(zmlin,'Visible','off');
            set(dlin,'Visible','off');
            set([zanglin(showlns);danglin(showlns)],'Visible','on');
            set([zanglin(~showlns);danglin(~showlns)],'Visible','off');
            hcirc.Visible = 'off';

            six=nd==lnnodes;
            set(skellns(~six),'LineWidth',1)
            skellns(six).LineWidth=3;
            set(zanglin,'EdgeAlpha',.2);
            set(danglin,'EdgeAlpha',.2);
            zanglin(six).EdgeAlpha = 1;
            danglin(six).EdgeAlpha = 1;
            six = find(six,1);

            wrap = skellns(six).UserData.wrap;
            if wrap==360
                wrap360btn.Enable = 'off';
                wrap180btn.Enable = 'on';
            else
                wrap360btn.Enable = 'on';
                wrap180btn.Enable = 'off';
            end
        else
            zoomax.Tag = 'Position';
            ylabel(zoomax,'Position (px)');
            ylabel(datax,'Position (px)');
            set(zmlin([showdlcpts showdlcpts]),'Visible','on');
            set(zmlin(~[showdlcpts showdlcpts]),'Visible','off');
            set(dlin([showdlcpts showdlcpts]),'Visible','on');
            set(dlin(~[showdlcpts showdlcpts]),'Visible','off');
            set([zanglin;danglin],'Visible','off');
            if ~isempty(nd)
                cix=find(nd==ptnodes, 1);
                if ~isempty(cix)
                    if showpts(cix)
                        hcirc.Visible = 'on';
                        hcirc.XData = roipts(cix).Position(1);
                        hcirc.YData = roipts(cix).Position(2);
                    else
                        hcirc.Visible = 'off';
                    end
                    if cix<=numdlcpts
                        set(zmlin,'EdgeAlpha',.2);
                        set(dlin,'EdgeAlpha',.2)
                        zmlin(cix,1).EdgeAlpha = 1;
                        zmlin(cix,2).EdgeAlpha = 1;
                        dlin(cix,1).EdgeAlpha = 1;
                        dlin(cix,2).EdgeAlpha = 1;
                    end
                else
                    hcirc.Visible = 'off';
                end
            else
                hcirc.Visible = 'off';
            end
            wrap180btn.Enable = 'off';
            wrap360btn.Enable = 'off';
        end
        updatehist;

        if strcmp(e.EventName, 'SelectionChanged')
            if strcmp(vtimer.running,'off') & tabgp.SelectedTab == datatab
                if ~isempty(six)
                    cix=find(strcmp(skellns(six).Tag,disptbl.Data.Properties.VariableNames));
                elseif (isempty(cix)||cix>numdlcpts)||xlut(cix)==0
                    ix=find(h.SelectedNodes==marknodes);
                    if isempty(ix)
                        cix = width(disptbl.Data);
                    else
                        cix=find(strcmp(erec(ix).Name,disptbl.Data.Properties.VariableNames));
                    end
                else
                    cix = xlut(cix);
                end
                scroll(disptbl,"row",fix);
                scroll(disptbl,"column",cix)
                if isfield(e,'Style')
                    addStyle(disptbl,e.Style,"cell",[[fix;fix] [cix; cix+1]]);
                end
                focus(ptstree);
            end
        end
    end

    % function oldnodecb(h,e)
    %     showpts = ismember(ptnodes, h.CheckedNodes);
    %     showdlcpts = showpts(1:numdlcpts);
    %     showlns = ismember(lnnodes, h.CheckedNodes);
    %     showmarks = ismember(marknodes,h.CheckedNodes);
    %     if isempty(h.SelectedNodes)
    %         cix = [];
    %         hcirc.Visible = 'off';
    %     else
    %         cix = find(h.SelectedNodes == ptnodes);
    %         if cix>numdlcpts
    %             hcirc.Visible = 'off';
    %             set(goodbadlns,'YData',vltempY);
    %         end
    %     end
    %     if ~isempty(cix) && cix<=numdlcpts
    %         foregroundpoint(cix);
    %         if showpts(cix) && dtab{fix,cix*3}==inf 
    %             revertbtn.Enable = 'on';
    %         else
    %             revertbtn.Enable = 'off';
    %         end
    %     elseif histviewbtn.UserData{4}<3
    %         set(histpts,'Visible','off');
    %     end        
    % 
    %     set(skellns,'LineWidth',1);
    %     if isempty(skellns) | isempty(h.SelectedNodes)
    %         six = [];
    %     else
    %         six=find(strcmp(h.SelectedNodes.Text,{skellns.Tag}));
    %     end
    %     if isempty(six)
    %         zoomax.Tag = 'Position';
    %         ylabel(zoomax,'Position (px)');
    %         ylabel(datax,'Position (px)');
    %         set(zmlin([showdlcpts showdlcpts]),'Visible','on');
    %         set(zmlin(~[showdlcpts showdlcpts]),'Visible','off');
    %         set(dlin([showdlcpts showdlcpts]),'Visible','on');
    %         set(dlin(~[showdlcpts showdlcpts]),'Visible','off');
    %         set([zanglin;danglin],'Visible','off');
    %     else
    %         skellns(six).LineWidth=3;
    %         set(zanglin,'EdgeAlpha',.2);
    %         set(danglin,'EdgeAlpha',.2);
    %         zanglin(six).EdgeAlpha = 1;
    %         danglin(six).EdgeAlpha = 1;
    % 
    %         zoomax.Tag = 'Angle';
    %         ylabel(zoomax,'Angle (°)');
    %         ylabel(datax,'Angle (°)');
    %         set(zmlin,'Visible','off');
    %         set(dlin,'Visible','off');
    %         set([zanglin(showlns);danglin(showlns)],'Visible','on');
    %         set([zanglin(~showlns);danglin(~showlns)],'Visible','off');
    %         hcirc.Visible = 'off';
    %     end
    % 
    %     switch e.EventName
    %         case 'CheckedNodesChanged'                 
    %             set(marklns(showmarks,:),'Visible','on');
    %             set(marklns(~showmarks,:),'Visible','off'); 
    % 
    %             if histviewbtn.UserData{4}==3
    %                 set(histpts(showdlcpts),'Visible','on');
    %                 set(histpts(~showdlcpts),'Visible','off');
    %             else           
    %                 set(histpts,'Visible','off');
    %                 if ((~isempty(cix) && cix<=numdlcpts)...
    %                         &&showpts(cix))&&histviewbtn.UserData{4}==2
    %                     histpts(cix).Visible = 'on';
    %                 end
    %             end
    % 
    %             ttab = dtab;
    %             ttab = [ttab atab(:,showlns)];
    %             if ~isempty(showmarks)
    %                 for i = 1:length(showmarks)
    %                     erec(i).Visible = showmarks(i);
    %                     if showmarks(i)
    %                         ttab = [ttab table(repmat(string,height(dtab),1),'VariableNames',{char(erec(i).Name)})];
    %                     end
    %                 end
    %             end
    %             ttab = [ttab disptbl.Data(:,end)];
    %             ttab(:,3:3:numdlccols)=[];
    %             xlut=1:2:numdlcpts*2;
    %             ylut=2:2:numdlcpts*2;
    %             ttab(:,[xlut(~showdlcpts) ylut(~showdlcpts)])=[];
    %             xlut = double(showdlcpts);
    %             xlut(showdlcpts)=1:2:sum(showdlcpts)*2;
    %             ylut = double(showdlcpts);
    %             ylut(showdlcpts)=2:2:sum(showdlcpts)*2;
    %             disptbl.Data = ttab;
    %             disptbl.ColumnWidth = 'auto';
    %             disptbl.ColumnWidth = [repmat({'fit'},[1 width(ttab)-1]) {'auto'}];
    %             ed = false(1,width(ttab));
    %             ed(end)=true;
    %             disptbl.ColumnEditable = ed;
    %             if tabgp.SelectedTab==datatab;tabcb(tabgp);end
    % 
    %             for i = find(showlns(:)')          
    %                 oix = find(skellns(i).UserData.origin==roipts);
    %                 tix = find(skellns(i).UserData.terminus==roipts);
    %                 if ~all(showpts([oix tix]));showlns(i)=0;end
    %             end
    %             set(skellns(showlns),'Visible','on');
    %             set(skellns(~showlns),'Visible','off');
    % 
    %             for i = 1:length(showmarks)
    %                 erec(i).Visible = showmarks(i);
    %             end
    %             set(marklns(showmarks,:),'Visible','on');
    %             set(marklns(~showmarks,:),'Visible','off');
    %             updateskellines;
    %             if strcmp(vtimer.running,'off')
    %                 set(roipts(showpts),'Visible','on');
    %                 set(roipts(~showpts),'Visible','off');                    
    %             end
    %         case 'SelectionChanged'                
    %             if strcmp(vtimer.running,'off') & tabgp.SelectedTab == datatab
    %                 if (isempty(cix)||cix>numdlcpts)||xlut(cix)==0                        
    %                     ix=find(h.SelectedNodes==marknodes);
    %                     if isempty(ix)
    %                         cix = width(disptbl.Data);
    %                     else
    %                         cix=find(strcmp(erec(ix).Name,disptbl.Data.Properties.VariableNames));
    %                     end
    %                 else
    %                     cix = xlut(cix);
    % 
    %                 end
    %                 scroll(disptbl,"row",fix);
    %                 scroll(disptbl,"column",cix)
    %                 if isfield(e,'Style')
    %                     addStyle(disptbl,e.Style,"cell",[[fix;fix] [cix; cix+1]]);
    %                 end
    %                 focus(ptstree);
    %             end              
    %     end
    % end

    function tblcb(h,e)
        switch e.EventName            
            case 'KeyPress'
                switch e.Key
                    case markshort
                        ix = find(strcmp(e.Key,markshort));
                        frix = h.Selection(:,1);
                        frix = min(frix):max(frix);
                        markframe(ix,frix);
                        cix=find(strcmp(erec(ix).Name,disptbl.Data.Properties.VariableNames));
                        if isempty(cix);return;end
                        h.Selection = [frix repmat(cix,size(frix))];
                    case {'r','delete'}
                        ptlut = repelem(find(showpts),2,1);
                        sel = h.Selection;
                        sel(sel(:,2)>sum(showpts)*2,:)=[];
                        pix=unique(ptlut(sel(:,2)));
                        rix=unique(sel(:,1));
                        for i = pix(:)'
                            cix=find(ptlut==i);
                            ccix = [i*3-2 i*3-1 i*3];
                            if strcmp(e.Key,'delete') %delete
                                dtab{rix,ccix(1:2)}=nan;
                                dtab{rix,ccix(3)}=inf;
                                h.Data{rix,cix}=nan;
                                zmlin(i,1).YData(rix)= nan;
                                zmlin(i,2).YData(rix)= nan;
                                dlin(i,1).YData(rix)= nan;
                                dlin(i,2).YData(rix)= nan;
                                histpts(i).XData(rix)= nan;
                                histpts(i).YData(rix)= nan;
                                roipts(i).Position = [-1 -1];
                                updatehist;
                                % goodbadlns(1).YData(vllut(rix))=1;
                                % goodbadlns(2).YData(vllut(rix))=nan;
                                % goodbadlns(3).YData(vllut(rix))=1;
                                % goodbadlns(4).YData(vllut(rix))=nan;
                            else %revert
                                dtab{rix,ccix}=ctab{rix,ccix};                               
                                h.Data{rix,cix}=ctab{rix,ccix(1:2)};
                                xval = ctab{rix,ccix(1)};
                                yval = ctab{rix,ccix(2)};
                                pval = ctab{rix,ccix(3)};
                                zmlin(i,1).YData(rix)= xval;
                                zmlin(i,2).YData(rix)= yval;
                                dlin(i,1).YData(rix)= xval;
                                dlin(i,2).YData(rix)= yval;
                                histpts(i).XData(rix)= xval;
                                histpts(i).YData(rix)= yval;
                                roipts(i).Position=ctab{fix,ccix(1:2)};
                                updatehist;
                                % goodbadlns(1).YData(vllut(rix))=nan;                                
                                % goodbadlns(2).YData(vllut(rix))=nan;
                                % goodbadlns(3).YData(vllut(rix))=nan;                                
                                % goodbadlns(4).YData(vllut(rix))=nan;
                                % isBad = pval<badlinthresh;
                                % if sum(isBad)>0
                                %     goodbadlns(2).YData(vllut(rix(isBad)))=1;
                                %     goodbadlns(4).YData(vllut(rix(isBad)))=1;
                                % end
                            end
                            revertbtn.Enable = 'on';
                        end
                        updateskellines(pix,true);
                        tabcb(tabgp,[]);
                    case 'space'
                        if isempty(erec);return;end
                        cix = unique(h.Selection(:,2));
                        mix = [];
                        for c = cix(:)'
                            mix=[mix find(strcmp([erec.Name],disptbl.Data.Properties.VariableNames(c)))];
                        end
                        if isempty(mix);return;end 
                        frix = h.Selection(:,1);
                        frix = min(frix):max(frix);
                        markframe(mix,frix);
                    case {'uparrow','downarrow'}
                        if ~any(strcmp(e.Modifier,'control'));return;end
                        if h.Selection(2)<=sum(showpts)*2
                            ptlut = repelem(find(showpts),2,1);
                            cix = ptlut(h.Selection(2))*3;
                            targix = find(dtab{:,cix}==inf | dtab{:,cix}<badlinthresh);
                        else
                            mix=find(strcmp([erec.Name],disptbl.Data.Properties.VariableNames(h.Selection(2))));
                            if isempty(mix);return;end
                            targix = erec(mix).FrameIndex;
                        end
                        if any(strcmp(e.Key,'uparrow'))
                            targix = targix(targix<h.Selection(1));
                            if isempty(targix)
                                h.Selection(1) = 1;
                            else
                                h.Selection(1) = targix(end);
                            end
                        else
                            targix = targix(targix>=h.Selection(1));
                            if isempty(targix)
                                h.Selection(1) = numframes;
                            else
                                h.Selection(1) = targix(1);
                            end
                        end
                        n = struct;
                        n.Selection = h.Selection;
                        n.EventName = 'SelectionChanged';
                        tblcb(h,n);
                        scroll(h,'row',h.Selection(1));
                end
            case 'CellEdit'
                    cix = e.Indices(2);
                    rix = e.Indices(1);
            case 'SelectionChanged'
                val = e.Selection;
                if all(val(:,1)==val(1))
                    if all(size(val)==[1 2])
                        if val(2)<=sum(showpts)*2
                            ptlut = repelem(find(showpts),2,1);
                            cix = ptlut(val(2));
                            if (isempty(ptstree.SelectedNodes) || ptstree.SelectedNodes ~= ptnodes(cix))
                                setnode(ptnodes(cix));
                                focus(h);
                            end
                        elseif val(2)<width(h.Data)
                            nm=disptbl.Data.Properties.VariableNames(val(2));
                            if ~isempty(lnnodes)
                                cix=find(strcmp(nm,{lnnodes.Text}));
                                if ~isempty(cix)
                                    setnode(lnnodes(cix));
                                    focus(h);
                                end
                            end
                        end
                    end
                    setframe(val(1));                    
                end
                if size(val,1)==1
                    dselrgn.XData = [nan nan];
                    zselrgn.XData = [nan nan];
                else
                    lim = [min(val(:,1)) max(val(:,1))];
                    dselrgn.XData = lim;
                    zselrgn.XData = lim;
                end
        end
    end

    function tabcb(h,e)
        switch h.SelectedTab
            case datatab
                removeStyle(disptbl)
                pmat = dtab{:,3:3:numdlccols};
                pmat = pmat(:,showpts(1:numdlcpts));
                pmat = repelem(pmat,1,2);
                [rx,cx]=find(pmat<badlinthresh);
                addStyle(disptbl,redstyle,"Cell",[rx,cx]);
                [rx,cx]=find(pmat==inf);
                addStyle(disptbl,greenstyle,"Cell",[rx,cx]);
                for i = 1:length(showmarks)
                    if ~showmarks(i)|isempty(erec(i).FrameIndex);continue;end
                    cix=find(strcmp(disptbl.Data.Properties.VariableNames,erec(i).Name));
                    frix = erec(i).FrameIndex(:);
                    % iix = [frix repmat(cix,size(frix))];
                    s = uistyle("BackgroundColor",erec(i).Col);
                    % addStyle(disptbl,s,"cell",iix);
                    for j = frix(:)'%stupid but do it 1-at-a-time so we can remove easily later for just one cell
                        addStyle(disptbl,s,"cell",[j cix]);
                    end
                end
            case plottab
                for i = 1:numel(zmlin)
                    dlin(i).YData = zmlin(i).YData; 
                end
        end
    end
    
    function setnode(node)
        if ~isempty(ptstree.SelectedNodes) && ptstree.SelectedNodes == node
            return
        end
        ptstree.SelectedNodes = node;
        n = struct;
        n.EventName = 'SelectionChanged';
        nodecb(ptstree,n)
    end

    % function foregroundpoint(cix)
    %     if histviewbtn.UserData{4}<3
    %         set(histpts,'Visible','off');
    %     end
    %     if cix<=numdlcpts && showpts(cix)
    %         hcirc.Visible = 'on';
    %         hcirc.XData = roipts(cix).Position(1);
    %         hcirc.YData = roipts(cix).Position(2);
    %         set(zmlin,'EdgeAlpha',.2);
    %         set(dlin,'EdgeAlpha',.2)
    %         zmlin(cix,1).EdgeAlpha = 1;
    %         zmlin(cix,2).EdgeAlpha = 1;
    %         dlin(cix,1).EdgeAlpha = 1;
    %         dlin(cix,2).EdgeAlpha = 1;
    %         if histviewbtn.UserData{4}==2 && ismember(ptnodes(cix), ptstree.CheckedNodes)
    %             histpts(cix).Visible = 'on';
    %         end
    %         goodix = dtab{:,cix*3}==inf;
    %         goodbadlns(1).YData(vllut(goodix))=1;
    %         goodbadlns(3).YData(vllut(goodix))=1;
    %         goodbadlns(1).YData(vllut(~goodix))=nan;
    %         goodbadlns(3).YData(vllut(~goodix))=nan;
    %         badix = dtab{:,cix*3}<badlinthresh;
    %         goodbadlns(2).YData(vllut(badix))=1;
    %         goodbadlns(4).YData(vllut(badix))=1;            
    %         goodbadlns(2).YData(vllut(~badix))=nan;
    %         goodbadlns(4).YData(vllut(~badix))=nan;
    %     else
    %         hcirc.Visible = 'off';
    %         set(zmlin,'EdgeAlpha',.2);
    %         set(dlin,'EdgeAlpha',.2)
    %         set(goodbadlns,'YData',vltempY);
    %     end
    % end

    function updatecolor(name,tag,newcol)   
        if strcmp(tag,'root');return;end
        if nargin<3
            if strcmp(tag,'Event')
                colix = strcmp(name,{marknodes.Text});
                oldcol = marknodes(colix).UserData; 
            else
                colix = strcmp(name,[ptslistL.ItemsData.name]);
                oldcol = ptslistL.ItemsData(colix).color;
            end
            newcol = uisetcolor(oldcol);
            if all(newcol==oldcol);focus(f);return;end
        end
        switch tag
            case {'DLC','Fixed'}
                idx = find(strcmp(name,{ptnodes.Text}));
                if strcmp(tag,'DLC')
                    ptnodes(idx).UserData = newcol;
                    histpts(idx).MarkerEdgeColor = newcol;
                    zmlin(idx,1).EdgeColor = newcol;
                    zmlin(idx,2).EdgeColor = newcol;
                    dlin(idx,1).EdgeColor = newcol;
                    dlin(idx,2).EdgeColor = newcol;
                    scpts.CData(idx,:)=newcol;
                end
                roipts(idx).Color = newcol;
                idx = strcmp(name,[ptslistL.ItemsData.name]);
                ptslistL.ItemsData(idx).color = newcol;
            case {'Segment','Axis'}
                idx = strcmp(name,{lnnodes.Text});
                lnnodes(idx).UserData = newcol;
                skellns(idx).Color = newcol;
                idx = strcmp(name,[ptslistL.ItemsData.name]);
                ptslistL.ItemsData(idx).color = newcol;
            case 'Event'
                idx = strcmp(name,{marknodes.Text});
                markcol(idx,:)=newcol;
                s = uistyle('BackgroundColor',newcol);
                addStyle(marktab,s,"cell",[find(idx) 2]);
                erec(idx).Col = newcol;
                set(marklns(idx,1:4),'Color',newcol);
                set(marklns(idx,5:6),'FaceColor',newcol);
                marknodes(idx).UserData = newcol;
        end        
        refreshpts()
        focus(f);
    end
 
    function restackhandles()
        hand = get(vidax,'Children');
        pix = isgraphics(hand,'images.roi.Point');
        hix = false(size(pix));
        lix = hix;

        [~,hiix]=ismember(histpts,hand);
        hix(hiix)=true;
        [~,liix]=ismember(skellns,hand);
        lix(liix)=true;

        cix = hand==hcirc;
        six = hand==scpts;
        oix = ~((((pix | cix)| hix)|six)|lix);
        hand=[hand(pix); hand(cix);hand(six);hand(lix);hand(hix); hand(oix)];
        set(vidax,'Children',hand);
    end

    function refreshpts()
        removeStyle(ptslistL);
        removeStyle(ptslistR);
        items = ptslistL.ItemsData;
        ptslistR.ItemsData = items;
        for i = 1:length(items)
            dat = items(i);
            if strcmp(dat.Tag,'Root')
                s = uistyle('FontWeight','bold','Icon','');                
            else                
                s = uistyle('Icon',col2ico(items(i).color),'FontWeight','normal');
            end
            addStyle(ptslistL,s,'item',i)
            addStyle(ptslistR,s,'item',i)
        end
        removeStyle(ptstree);drawnow
        for i = [dlcroot fxdroot segroot eventroot ptnodes(:)' lnnodes(:)' marknodes(:)']
            if strcmp(i.Tag,'Root')
                s = boldwithIco;
            else
                s = uistyle('Icon',col2ico(i.UserData),'FontWeight','normal');
            end
            addStyle(ptstree,s,"node",i);
        end        
    end

    function skelcb(h,e)
        toggles = [editsel,fixedsel,segsel,axissel];
        mode = find(~cell2mat(get(toggles,'Value')));
        switch h
            case {editsel,fixedsel,segsel,axissel}
                idx = h == toggles;
                set(toggles(idx),'Value',0,'BackgroundColor',[173,216,230]./255,'FontColor','k');
                if strcmp(themecol,'k')
                    set(toggles(~idx),'Value',1,'BackgroundColor',[0.96 0.96 0.96],'FontColor',themecol);                    
                else
                    set(toggles(~idx),'Value',1,'BackgroundColor',[0 0 0],'FontColor',themecol);
                end
                if h==editsel
                    addskelbtn.Text = 'Update';
                    remskelbtn.Text = 'Revert Changes';                   
                else
                    addskelbtn.Enable = 'on';
                    addskelbtn.Text = 'Add';
                    remskelbtn.Text = 'Remove';
                    skelnameedit.Value = "";
                    skelcoledit.ImageSource = cat(3,.7,.7,.7);
                    skelcoledit.UserData = [.7 .7 .7];
                end
                if any(h == [segsel axissel])
                    ptslistR.Enable = 'on';
                else
                    ptslistR.Enable = 'off';
                end
                skelcb(ptslistL,[]);
            case skelnameedit
                if ~strcmp(e.EventName,'ValueChanging');return;end
                badnames=string(ptslistL.Items);
                if ~isempty(erec)
                    badnames = [badnames string({erec.Name})];
                end
                if any(strcmp(e.Value,badnames))
                    addskelbtn.Enable = 'off';
                    remskelbtn.Enable = 'off';
                else
                    addskelbtn.Enable = 'on';
                    remskelbtn.Enable = 'on';
                end

            case skelcoledit
                col = uisetcolor(h.UserData);
                h.UserData = col;
                h.ImageSource = cat(3,col(1),col(2),col(3));
                focus(h);
            case addskelbtn
                switch mode
                    case 1
                        newname = skelnameedit.Value;
                        ix = ptslistL.ValueIndex;
                        dat = ptslistL.ItemsData(ix);
                        if dat.Tag=="root";return;end
                        dat.name = newname;
                        dat.color = skelcoledit.UserData;
                        ptslistL.ItemsData(ix)=dat;
                        ptslistL.Items{ix}=newname;
                        ptslistL.ValueIndex = ix;
                        remskelbtn.Enable = 'on';
                        updatecolor(dat.name,dat.Tag,dat.color);
                        roipts(ix-1).Label=dat.name;                        
                    case 2
                        items = ptslistL.ItemsData;
                        ix = find(strcmp([items.name],'Lines and Angles')&strcmp([items.Tag],'Root'));
                        dat = items(ix);
                        dat.name = skelnameedit.Value;
                        dat.csvname = dat.name;
                        dat.color = skelcoledit.UserData;
                        dat.origcolor = dat.color;
                        dat.Tag = 'Fixed';
                        items = [items(1:ix-1) dat items(ix:end)];
                        lst = ptslistL.Items;
                        lst = [lst(1:ix-1) {char(dat.name)} lst(ix:end)];
                        ptslistL.ItemsData = items;
                        ptslistL.Items = lst;
                        ptslistL.ValueIndex = ix;
                        
                        ptslistR.ItemsData = items;
                        ptslistR.Items = lst;

                        ptnodes = [ptnodes; uitreenode(fxdroot,'Text',dat.name,'NodeData',dat,'Tag',"Fixed",'UserData',dat.color)];
                        ptstree.CheckedNodes = [ptstree.CheckedNodes; ptnodes(end)];
                        expand(fxdroot);

                        pos = [vr.Width/2 vr.Height/2];
                        udat = struct;
                        udat.ix = length(roipts)+1;
                        udat.memberlines = [];
                        udat.memberlineix = [];
                        udat.memberlinetype = [];
                        udat.memberlinepartner = [];
                        roipts = [roipts; images.roi.Point(vidax,'Position',pos,...
                            'Color',dat.color,'Label',dat.name,'ContextMenu',[],...
                            'Deletable',false,'LabelVisible',labvis,'UserData',...
                            udat)];
                        addlistener(roipts(end),'ROIClicked',@ptcb);
                        addlistener(roipts(end),'MovingROI',@ptcb);
                        addlistener(roipts(end),'ROIMoved',@ptcb);
                        n = struct;
                        n.EventName = 'CheckedNodesChanged';
                        nodecb(ptstree,n);
                        refreshpts;
                    case {3 4}
                        if mode ==3
                            lstyle = '-';
                            ltype = 0;
                            ltag = "Segment";
                        else
                            lstyle = '--';
                            ltype = 1;
                            ltag = "Axis";
                        end
                        origin = ptslistL.Value;
                        oix = ptslistL.ValueIndex-1;
                        if origin.Tag=="Fixed"
                            oix = oix-1;
                        end

                        terminus = ptslistR.Value;
                        tix = ptslistR.ValueIndex-1;
                        if terminus.Tag=="Fixed"
                            tix = tix-1;
                        end
                        
                        items = ptslistL.ItemsData;
                        dat = struct;
                        dat.name = skelnameedit.Value;
                        if isempty(char(dat.name))
                            dat.name = strcat(origin.name,'->',terminus.name);
                        end
                        dat.csvname = dat.name;
                        dat.color = skelcoledit.UserData;
                        dat.origcolor = dat.color;
                        dat.Tag = ltag;
                        items = [items dat];
                        lst = ptslistL.Items;
                        lst = [lst {char(dat.name)}];
                        ptslistL.ItemsData = items;
                        ptslistL.Items = lst;
                        ptslistR.ItemsData = items;
                        ptslistR.Items = lst;

                        lnnodes = [lnnodes; uitreenode(segroot,'Text',dat.name,'NodeData',dat,'Tag',ltag,'UserData',dat.color)];
                        ptstree.CheckedNodes = [ptstree.CheckedNodes; lnnodes(end)];
                        expand(segroot);
                        ico = col2ico(dat.color);
                        tstyle = uistyle("Icon",ico,'FontWeight','normal');
                        addStyle(ptstree,tstyle,"node",lnnodes(end));
                        refreshpts;
                        
                        udat = struct;
                        udat.name = dat.name;
                        udat.origin = roipts(oix);
                        udat.terminus = roipts(tix);
                        udat.dispnode = lnnodes(end);
                        udat.wrap = 360;
                        skellns = [skellns plot(vidax,[nan,nan],[nan,nan],'Color',dat.color,...
                            'Tag',dat.name,'UserData',udat,'LineStyle',lstyle)];

                        restackhandles();

                        roipts(oix).UserData.memberlines = [roipts(oix).UserData.memberlines skellns(end)];
                        roipts(oix).UserData.memberlineix(end+1)=1;
                        roipts(oix).UserData.memberlinetype(end+1)=ltype;
                        roipts(oix).UserData.memberlinepartner = [roipts(oix).UserData.memberlinepartner roipts(tix)];

                        roipts(tix).UserData.memberlines = [roipts(tix).UserData.memberlines skellns(end)];
                        roipts(tix).UserData.memberlineix(end+1)=2;
                        roipts(tix).UserData.memberlinetype(end+1)=ltype;
                        roipts(tix).UserData.memberlinepartner = [roipts(tix).UserData.memberlinepartner roipts(oix)];
                        
                        ptslistL.ValueIndex = length(lst);
                        ptslistR.ValueIndex = length(lst);
                        
                        if oix>numdlcpts
                            odat = repmat(roipts(oix).Position,numframes,1);
                        else
                            odat = [dtab{:,[oix*3-2 oix*3-1]}];
                        end
                        if tix>numdlcpts
                            tdat = repmat(roipts(tix).Position,numframes,1);
                        else
                            tdat = [dtab{:,[tix*3-2 tix*3-1]}];
                        end
                        ang = wrapTo360(atan2d(tdat(:,2)-odat(:,2),tdat(:,1)-odat(:,1)));
                        yyaxis(datax,'left');
                        yyaxis(zoomax,'left');
                        zanglin = [zanglin; lineAlphaFcn(zoomax,1:numframes,ang,dat.color,.2,'ButtonDownFcn',@buttons,'Visible','off','Tag',dat.name)];
                        danglin = [danglin; lineAlphaFcn(datax,1:numframes,ang,dat.color,.1,'ButtonDownFcn',@buttons,'Visible','off','Tag',dat.name)];
                        atab = [atab table(ang,'VariableNames',{char(dat.name)})];

                        n = struct;
                        n.EventName = 'CheckedNodesChanged';
                        nodecb(ptstree,n);
                        updateskellines;
                        addskelbtn.Enable = 'off';
                end
            case remskelbtn
                switch mode
                    case 1
                        ix = ptslistL.ValueIndex;
                        dat = ptslistL.ItemsData(ix);
                        skelnameedit.Value = dat.csvname;
                        skelcoledit.UserData = dat.origcolor;
                        skelcoledit.ImageSource = col2ico(dat.origcolor);
                        if strcmp(dat.name,dat.csvname)&&all(dat.origcolor==dat.color);return;end
                        dat.name = dat.csvname;
                        dat.color = dat.origcolor;
                        ptslistL.ItemsData(ix)=dat;
                        lst = ptslistL.Items;
                        lst{ix}=char(dat.csvname);
                        ptslistL.Items = lst;
                        ptslistL.ValueIndex = ix;
                        updatecolor(dat.name,dat.Tag,dat.origcolor);
                        roipts(ix-1).Label = dat.csvname;
                    case 2
                        ix = ptslistL.ValueIndex;
                        dat = ptslistL.ItemsData(ix);
                        if ~strcmp(dat.Tag,'Fixed');return;end
                        items = ptslistL.ItemsData;
                        lst = ptslistL.Items;
                        items(ix)=[];
                        lst(ix)=[];
                        ptslistL.Items = lst;
                        ptslistR.Items = lst;
                        ptslistL.ItemsData = items;
                        ptslistR.ItemsData = items;
                        ix = ix-2;
                        prunelines(roipts(ix).UserData.memberlines);
                        delete(roipts(ix));
                        roipts(ix) = [];
                        delete(ptnodes(ix));
                        ptnodes(ix) = [];
                        refreshpts;
                        addskelbtn.Enable = 'off';
                    case {3 4}
                        dat = ptslistL.Value;
                        if ~strcmp(dat.Tag,'Segment') && ~strcmp(dat.Tag,'Axis');return;end
                        prunelines(skellns(strcmp(get(skellns,'Tag'),dat.name)));
                        refreshpts;
                end
            case {ptslistL ptslistR}
                dat = h.Value;
                isL=true;
                if dat.Tag=="Root"
                    skelnameedit.Enable = 'off';
                    skelcoledit.Enable = 'off';
                    addskelbtn.Enable = 'off';
                    remskelbtn.Enable = 'off';
                    return
                elseif h==ptslistR
                    isL=false;
                end
                skelnameedit.Enable = 'on';
                skelcoledit.Enable = 'on';
                switch mode
                    case 1
                        skelnameedit.Enable = 'off';
                        skelnameedit.Value = dat.name;
                        skelcoledit.ImageSource = col2ico(dat.color);
                        skelcoledit.UserData = dat.color;
                        if ~strcmp(dat.name,dat.csvname)
                            remskelbtn.Enable = 'on';
                        else
                            remskelbtn.Enable = 'off';
                        end
                        if ~strcmp(dat.name,skelnameedit.Value)
                            addskelbtn.Enable = 'on';
                        else
                            addskelbtn.Enable = 'off';
                        end
                    case 2
                        skelcoledit.ImageSource = col2ico(dat.color);
                        skelcoledit.UserData = dat.color;

                        if isempty(char(skelnameedit.Value))
                            addskelbtn.Enable = 'off';
                        else
                            addskelbtn.Enable = 'on';
                        end

                        if strcmp(dat.Tag,'Fixed')
                            remskelbtn.Enable = 'on';
                        else
                            remskelbtn.Enable = 'off';
                        end
                    case {3,4}
                        if isL
                            skelcoledit.ImageSource = col2ico(dat.color);
                            skelcoledit.UserData = dat.color;
                        end
                        if (mode==3 && strcmp(dat.Tag,'Segment')) ||...
                            (mode==4 && strcmp(dat.Tag,'Axis'))
                            remskelbtn.Enable = 'on';
                        else
                            remskelbtn.Enable = 'off';
                        end
                        nameL=ptslistL.Value.name;
                        nameR=ptslistR.Value.name;
                        tagL = ptslistL.Value.Tag;
                        tagR = ptslistR.Value.Tag;
                        isPtL = any(strcmp(tagL,{'DLC','Fixed'}));
                        isPtR = any(strcmp(tagR,{'DLC','Fixed'}));
                        if ~strcmp(nameL,nameR) && (isPtL && isPtR)
                            addskelbtn.Enable = 'on';
                        else
                            addskelbtn.Enable = 'off';
                        end
                end
        end
    end

    function ico = col2ico(col)
        ico = cat(3,col(1),col(2),col(3));
    end

    function updatesel()
        lim = dselrgn.XData;
        if any(isnan(lim))
            disptbl.Selection = [];
            return
        end
        rix = lim(1):lim(2);
        rix = rix';
        cn = ptstree.CheckedNodes;
        sn = ptstree.SelectedNodes;

        cols = 1:width(disptbl.Data);
        if ~(isempty(sn)||~ismember(sn,cn))
            n = sn.Text;
            if ismember(sn,ptnodes(1:numdlcpts))
                cols = find(contains(disptbl.Data.Properties.VariableNames(1:sum(showpts(1:numdlcpts))*2),n));
            elseif ismember(sn,marknodes)
                cols = find(strcmp(n,disptbl.Data.Properties.VariableNames));
            elseif ismember(sn,lnnodes)            
                lix = sn==lnnodes;
                ln = skellns(lix).UserData;
                ct = find(contains(disptbl.Data.Properties.VariableNames(1:sum(showpts(1:numdlcpts))*2),ln.origin.Label));
                ct = [ct find(contains(disptbl.Data.Properties.VariableNames(1:sum(showpts(1:numdlcpts))*2),ln.terminus.Label))];
                if ~isempty(ct);cols = ct;end
            end
        end
        sel = [];
        for cix = cols(:)'
            sel = [sel; rix repelem(cix,numel(rix),1)];
        end
        disptbl.Selection = sel;
    end
    
    function buttons(h,e)
        switch h
            % case f
            %     if ~strcmp(e.EventName,'WindowScrollWheel');return;end
            %     if isempty(ptstree.SelectedNodes);return;end                
            %     idx = find(ptstree.SelectedNodes == ptnodes);
            %     if ~isempty(idx)                    
            %         idx = idx+e.VerticalScrollCount;
            %         if idx>length(ptnodes)
            %             idx = 1;
            %         elseif idx<1
            %             idx = length(ptnodes);
            %         end
            %         ptstree.SelectedNodes = ptnodes(idx);
            %         n = struct;
            %         n.EventName = 'SelectionChanged';
            %         nodecb(ptstree,n);
            %     end
            case {vidim,hcirc}               
                if isRunning;return;end
                if any(ismember(ptnodes,ptstree.SelectedNodes))
                    ix = ptnodes==ptstree.SelectedNodes;
                    if ~showpts(ix);return;end
                    if e.Button == 1
                        roipts(ix).Position = e.IntersectionPoint(1:2);
                        n = struct;
                        n.EventName = 'ROIMoved';
                        ptcb(roipts(ix),n);
                    elseif e.Button == 3
                        buttons(revertbtn,[]);
                    end
                end
            case zmwind
                if isRunning;return;end
                xlim(zoomax, [fix-h.Value/2 fix+h.Value/2])
            case {ptslistL ptslistR}
                ix = e.InteractionInformation.Item;
                dat= e.Source.ItemsData(ix);
                updatecolor(dat.name,dat.Tag);
            case ptstree
                tag = string(get(ptstree.SelectedNodes,'Tag'));
                name = string(get(ptstree.SelectedNodes,'Text'));
                updatecolor(name,tag);

            case selstartbtn
                lim = dselrgn.XData;
                lim(1) = fix;
                if isnan(lim(2))
                    lim(2)=numframes;
                end
                if lim(1)>lim(2)
                    lim = fliplr(lim(:)');
                elseif lim(1)==lim(2)
                    lim = [nan nan];
                end
                dselrgn.XData = lim;
                zselrgn.XData = lim;
                updatesel;
                focus(f);
            case selstopbtn
                lim = dselrgn.XData;
                lim(2) = fix;
                if isnan(lim(1))
                    lim(1)=1;
                end
                if lim(1)>lim(2)
                    lim = fliplr(lim(:)');
                elseif lim(1)==lim(2)
                    lim = [nan nan];
                end
                dselrgn.XData = lim;
                zselrgn.XData = lim;
                updatesel;
                focus(f);
            case selresetbtn
                dselrgn.XData = [nan nan];
                zselrgn.XData = [nan nan];
                updatesel;
                focus(f);
            case nanbtn
                cix = find((ptnodes == ptstree.SelectedNodes));
                if(isempty(cix));return;end
                if(cix>numdlcpts);return;end
                lim = dselrgn.XData;
                if any(isnan(lim))
                    ix = fix;
                else
                    ix = lim(1):lim(2);
                end
                ccix = [cix*3-2 cix*3-1 cix*3];
                val =[nan nan];
                dtab{ix,ccix} = repmat([nan,nan,inf],numel(ix),1);
                disptbl.Data{ix,[xlut(cix);ylut(cix)]}=repmat(val,numel(ix),1);
                for i = ix(:)'
                    addStyle(disptbl,greenstyle,'cell',[[i;i] [xlut(cix);ylut(cix)]]);
                end
                zmlin(cix,1).YData(ix)= nan;
                zmlin(cix,2).YData(ix)= nan;
                dlin(cix,1).YData(ix)= nan;
                dlin(cix,2).YData(ix)= nan;
                histpts(cix).XData(ix)= nan;
                histpts(cix).YData(ix)= nan;
                roipts(cix).Position = [-1 -1];
                revertbtn.Enable = 'on';
                hcirc.XData = nan;
                hcirc.YData = nan;
                updateskellines(cix);
                updatehist;
                focus(f);
                % goodbadlns(1).YData(vllut(fix))=1;
                % goodbadlns(2).YData(vllut(fix))=nan;
                % goodbadlns(3).YData(vllut(fix))=1;
                % goodbadlns(4).YData(vllut(fix))=nan;
            case interpbtn
                cix = find((ptnodes == ptstree.SelectedNodes));
                if(isempty(cix));return;end
                if(cix>numdlcpts);return;end
                ccix = [cix*3-2 cix*3-1 cix*3];
                lim = dselrgn.XData;
                if any(isnan(lim))
                    ix = fix;
                    bfr = dtab{fix-1,ccix(1:2)};
                    aft = dtab{fix+1,ccix(1:2)};
                    mn = mean([bfr;aft]);
                    val = mn;
                else
                    ix = lim(1):lim(2);
                    bfr = dtab{ix(1)-1,ccix(1:2)};
                    aft = dtab{ix(end)+1,ccix(1:2)};
                    val=[linspace(bfr(1),aft(1),numel(ix)+2);linspace(bfr(2),aft(2),numel(ix)+2)]';
                    val = val(2:end-1,:);
                end
                dtab{ix,ccix} = [val inf(numel(ix),1)];
                disptbl.Data{ix,[xlut(cix);ylut(cix)]}=val;
                for i = ix(:)'
                    addStyle(disptbl,greenstyle,'cell',[[i;i] [xlut(cix);ylut(cix)]]);
                end
                zmlin(cix,1).YData(ix)= val(:,1);
                zmlin(cix,2).YData(ix)= val(:,2);
                dlin(cix,1).YData(ix)= val(:,1);
                dlin(cix,2).YData(ix)= val(:,2);
                histpts(cix).XData(ix)= val(:,1);
                histpts(cix).YData(ix)= val(:,2);
                revertbtn.Enable = 'on';
                roipts(cix).Position = dtab{fix,ccix(1:2)};
                hcirc.XData = roipts(cix).Position(1);
                hcirc.YData = roipts(cix).Position(2);
                updateskellines(cix);
                updatehist;
                focus(f);

            % case interpbtn
            %     cix = find((ptnodes == ptstree.SelectedNodes));
            %     if(isempty(cix));return;end
            %     if(cix>numdlcpts);return;end
            %     ccix = [cix*3-2 cix*3-1 cix*3];
            %     bfr = dtab{fix-1,ccix(1:2)};
            %     aft = dtab{fix+1,ccix(1:2)};
            %     mn = mean([bfr;aft]);
            %     dtab(fix,ccix) = table(mn(1),mn(2),inf);
            %     disptbl.Data{fix,[xlut(cix);ylut(cix)]}=mn;
            %     addStyle(disptbl,greenstyle,'cell',[[fix;fix] [xlut(cix);ylut(cix)]]);
            %     zmlin(cix,1).YData(fix)= mn(1);
            %     zmlin(cix,2).YData(fix)= mn(2);
            %     dlin(cix,1).YData(fix)= mn(1);
            %     dlin(cix,2).YData(fix)= mn(2);
            %     histpts(cix).XData(fix)= mn(1);
            %     histpts(cix).YData(fix)= mn(2);
            %     roipts(cix).Position = mn;
            %     hcirc.XData = mn(1);
            %     hcirc.YData = mn(2);
            %     revertbtn.Enable = 'on';
            %     updateskellines(cix,true);
            %     updatehist;
            %     focus(f);
            %     % goodbadlns(1).YData(vllut(fix))=1;
            %     % goodbadlns(2).YData(vllut(fix))=nan;
            %     % goodbadlns(3).YData(vllut(fix))=1;
            %     % goodbadlns(4).YData(vllut(fix))=nan;
            case revertbtn
                cix = find((ptnodes == ptstree.SelectedNodes));
                if(isempty(cix));return;end
                if(cix>numdlcpts);return;end
                lim = dselrgn.XData;
                if any(isnan(lim))
                    ix = fix;
                else
                    ix = lim(1):lim(2);
                end
                ccix = [cix*3-2 cix*3-1 cix*3];
                dtab{ix,ccix}=ctab{ix,ccix};
                disptbl.Data{ix,[xlut(cix) ylut(cix)]} = ctab{ix,ccix(1:2)};
                zmlin(cix,1).YData(ix)= ctab{ix,ccix(1)};
                zmlin(cix,2).YData(ix)= ctab{ix,ccix(2)};
                dlin(cix,1).YData(ix)= ctab{ix,ccix(1)};
                dlin(cix,2).YData(ix)= ctab{ix,ccix(2)};
                histpts(cix).XData(ix)= ctab{ix,ccix(1)};
                histpts(cix).YData(ix)= ctab{ix,ccix(2)};
                roipts(cix).Position = ctab{fix,ccix(1:2)};
                revertbtn.Enable = 'off';
                if tabgp.SelectedTab == datatab
                    tabcb(tabgp,[])
                end
                hcirc.XData = dtab{fix,ccix(1)};
                hcirc.YData = dtab{fix,ccix(2)};
                updateskellines(find(showpts),true);
                updatehist;
                focus(f);
                % goodbadlns(1).YData(vllut(fix))=nan;
                % goodbadlns(3).YData(vllut(fix))=nan;
                % if dtab{fix,ccix(3)}<badlinthresh
                %     goodbadlns(2).YData(vllut(fix))=1;
                %     goodbadlns(4).YData(vllut(fix))=1;
                % else
                %     goodbadlns(2).YData(vllut(fix))=nan;
                %     goodbadlns(4).YData(vllut(fix))=nan;
                % end
            case nanrowbtn
                aix = find(showpts(1:numdlcpts));
                if(isempty(aix));return;end
                for cix = aix(:)'
                    ccix = [cix*3-2 cix*3-1 cix*3];
                    val =[nan nan];
                    dtab(fix,ccix) = table(nan,nan,inf);
                    disptbl.Data{fix,[xlut(cix);ylut(cix)]}=val;
                    addStyle(disptbl,greenstyle,'cell',[[fix;fix] [xlut(cix);ylut(cix)]]);
                    zmlin(cix,1).YData(fix)= val(1);
                    zmlin(cix,2).YData(fix)= val(2);
                    dlin(cix,1).YData(fix)= val(1);
                    dlin(cix,2).YData(fix)= val(2);
                    histpts(cix).XData(fix)= val(1);
                    histpts(cix).YData(fix)= val(2);
                    roipts(cix).Position = [-1 -1];
                    revertbtn.Enable = 'on';
                    updatehist;
                    % goodbadlns(1).YData(vllut(fix))=1;
                    % goodbadlns(2).YData(vllut(fix))=nan;
                    % goodbadlns(3).YData(vllut(fix))=1;
                    % goodbadlns(4).YData(vllut(fix))=nan;
                end
                updateskellines(aix,true);
                focus(f);
            case interprowbtn
                aix = find(showpts(1:numdlcpts));
                if(isempty(aix));return;end
                for cix = aix(:)'
                    ccix = [cix*3-2 cix*3-1 cix*3];
                    bfr = dtab{fix-1,ccix(1:2)};
                    aft = dtab{fix+1,ccix(1:2)};
                    mn = mean([bfr;aft]);
                    dtab(fix,ccix) = table(mn(1),mn(2),inf);
                    disptbl.Data{fix,[xlut(cix);ylut(cix)]}=mn;
                    addStyle(disptbl,greenstyle,'cell',[[fix;fix] [xlut(cix);ylut(cix)]]);
                    zmlin(cix,1).YData(fix)= mn(1);
                    zmlin(cix,2).YData(fix)= mn(2);
                    dlin(cix,1).YData(fix)= mn(1);
                    dlin(cix,2).YData(fix)= mn(2);
                    histpts(cix).XData(fix)= mn(1);
                    histpts(cix).YData(fix)= mn(2);
                    roipts(cix).Position = mn;
                    revertbtn.Enable = 'on';
                    updatehist;
                    % goodbadlns(1).YData(vllut(fix))=1;
                    % goodbadlns(2).YData(vllut(fix))=nan;
                    % goodbadlns(3).YData(vllut(fix))=1;
                    % goodbadlns(4).YData(vllut(fix))=nan;
                end
                updateskellines(aix,true);
                focus(f);
            case revertrowbtn
                aix = find(showpts(1:numdlcpts));
                if(isempty(aix));return;end
                for cix = aix(:)'
                    ccix = [cix*3-2 cix*3-1 cix*3];
                    dtab{fix,ccix}=ctab{fix,ccix};
                    disptbl.Data{fix,[xlut(cix) ylut(cix)]} = ctab{fix,ccix(1:2)};
                    zmlin(cix,1).YData(fix)= ctab{fix,ccix(1)};
                    zmlin(cix,2).YData(fix)= ctab{fix,ccix(2)};
                    dlin(cix,1).YData(fix)= ctab{fix,ccix(1)};
                    dlin(cix,2).YData(fix)= ctab{fix,ccix(2)};
                    histpts(cix).XData(fix)= ctab{fix,ccix(1)};
                    histpts(cix).YData(fix)= ctab{fix,ccix(2)};
                    roipts(cix).Position = ctab{fix,ccix(1:2)};
                    revertbtn.Enable = 'off';
                    if tabgp.SelectedTab == datatab
                        tabcb(tabgp,[])
                    end
                    updatehist;
                    % goodbadlns(1).YData(vllut(fix))=nan;
                    % goodbadlns(3).YData(vllut(fix))=nan;
                    % if dtab{fix,ccix(3)}<badlinthresh
                    %     goodbadlns(2).YData(vllut(fix))=1;
                    %     goodbadlns(4).YData(vllut(fix))=1;
                    % else
                    %     goodbadlns(2).YData(vllut(fix))=nan;
                    %     goodbadlns(4).YData(vllut(fix))=nan;
                    % end
                end
                updateskellines(aix,true);
                focus(f);
            case wrap180btn
                six = find(ismember(lnnodes,ptstree.SelectedNodes));
                if isempty(six);return;end
                wrap360btn.Enable = 'on';
                wrap180btn.Enable = 'off';
                skellns(six).UserData.wrap = 180;
                zanglin(six).YData = wrapTo180(zanglin(six).YData);
                danglin(six).YData = wrapTo180(danglin(six).YData);
                updatetablines;
            case wrap360btn
                six = find(ismember(lnnodes,ptstree.SelectedNodes));
                if isempty(six);return;end
                wrap360btn.Enable = 'off';
                wrap180btn.Enable = 'on';
                skellns(six).UserData.wrap = 360;
                zanglin(six).YData = wrapTo360(zanglin(six).YData);
                danglin(six).YData = wrapTo360(danglin(six).YData);
                updatetablines;
            case {zoomax,datax,zselrgn,dselrgn,goodbadlns,goodbadrgn}
                if e.Button == 2
                    dselrgn.XData = [nan nan];
                    zselrgn.XData = [nan nan];
                else
                    lfix = fix;
                    val=round(e.IntersectionPoint(1));
                    setframe(val);
                    if e.Button == 3 && lfix ~= fix
                        lim = sort([lfix fix]);
                        dselrgn.XData = lim;
                        zselrgn.XData = lim;
                    end
                end
                % lim = dselrgn.XData;
                % if all(~isnan(lim)) && (val<lim(1) || val>lim(2))
                %     dselrgn.XData = [nan nan];
                %     zselrgn.XData = [nan nan];
                % end
            case progax
                if isempty(ftab);return;end
                val = e.IntersectionPoint(1);
                val = round(val);
                setframe(val);
            case fpanel
                tdir = uigetdir;
                focus(f);
                if tdir==0;return;end
                updatedefaults;
                curdir = tdir;
                if strcmp(vtimer.running,'on');buttons(playpause);end
                [ftab, networks] = getfiles(tdir);
                networks =["All detected networks";networks];
                if ~isempty(ftab)
                    dispnames = ftab.dispname;
                    filenotes = ftab.filenote;
                    ftabix = 1:height(ftab);
                end
                h.Title = tdir;
                if ~isempty(ftab)
                    netdropdown.Items = networks;
                    netdropdown.ValueIndex=1;
                    flisttab.Data = table(dispnames,repmat(string,size(dispnames)),filenotes);
                    flisttab.Selection = [1 1];
                    loadvid(ftabix(1));
                else
                    flisttab.Data = table();
                    vidim.CData = zeros(size(vidim.CData));
                    progsld.Value = 1;
                    netdropdown.Items = "";
                    loadpanel.Visible ='on';                   
                    delete(roipts);
                    delete(skellns);
                    delete(scpts);
                    delete(histpts);
                    markshort = [];
                    fileix = [];
                end
            case flisttab
                % if strcmp(e.EventName,'SelectionChanged')
                %     rix = e.Selection(1);
                %     cix = e.Selection(2);
                %     if ~isempty(e.PreviousSelection)
                %         prix = e.PreviousSelection(1);
                %     else
                %         prix = 0;
                %     end
                %     if prix~=rix
                %         loadvid(ftabix(rix));
                %     end
                % end
                if strcmp(e.EventName,'DoubleClicked') ||...
                        (strcmp(e.EventName,'KeyPress')&&...
                        strcmp(e.Key,'return'))
                    rix = h.Selection(1);
                    cix = h.Selection(2);
                    if cix==3;return;end
                    prix=find(ftabix==fileix);
                    if rix==prix;return;end
                    loadvid(ftabix(rix));               
                end
            case exportconfbtn
                DLCProofConfig = exportconfig;
                fname = strcat('DLCProofConfig_',ftab.netname(fileix),'.mat');
                uisave('DLCProofConfig',fname);
            case importconfbtn
                [fname,fpath] = uigetfile('*.mat');
                if fname==0;return;end
                fname = fullfile(fpath,fname);
                DLCProof = [];
                DLCProofConfig =[];
                load(fname);
                if ~isempty(DLCProof)&isfield(DLCProof,'Configuration')
                    importconfig(DLCProof.Configuration);
                elseif ~isempty(DLCProofConfig)
                    importconfig(DLCProofConfig);
                else
                    msgbox('No useable configuration detected');
                    return
                end
                n = struct;
                n.EventName='CheckedNodesChanged';
                nodecb(ptstree,n)
                refreshpts;
                updateskellines;
            case setdefconfbtn
                conf = exportconfig;
                ix = find(strcmp(conf.Network,defnetset.Network));
                if isempty(ix)
                    defnetset = [defnetset;...
                        table(conf.Network,conf,...
                        'VariableNames',{'Network','Config'})];
                else
                    defnetset.Config(ix)=conf;
                end
                save(netdeffile,'defnetset');
                resetnetbtn.Enable='on';
            case resetnetbtn
                conf = exportconfig;
                ix = find(strcmp(conf.Network,defnetset.Network));
                if ~isempty(ix)
                     defnetset(ix,:)=[];
                else
                    return;
                end
                save(netdeffile,'defnetset');
                resetnetbtn.Enable='off';
            case netdropdown
                if isempty(ftab);return;end
                if h.ValueIndex==1 %All Files
                    ftabix = 1:height(ftab);
                else %Selected Network
                    ftabix=find(strcmp(ftab.netname,h.Value));
                end
                dispnames = ftab.dispname(ftabix);
                filenotes = ftab.filenote(ftabix);
                flisttab.Data = table(dispnames,repmat(string,size(dispnames)),filenotes);
                rix =find(ftabix == fileix);
                if isempty(rix)
                    flisttab.Selection = [1 1];
                    loadvid(ftabix(1));
                else
                    flisttab.Selection = [rix 1];
                    refreshfilesavelabels
                end
            case prevfilebtn
                if isempty(ftab);return;end
                if isempty(flisttab.Selection)
                    return;
                else
                    val = find(ftabix==fileix)-1;
                end
                if val<1;return;end
                flisttab.Selection = [val 1];
                v = struct;
                v.EventName = 'DoubleClicked';
                buttons(flisttab,v)            
            case nextfilebtn
                if isempty(ftab);return;end
                if isempty(flisttab.Selection)
                    val = 2;
                else
                    val = find(ftabix==fileix)+1;
                end
                if val>height(flisttab.Data);return;end
                flisttab.Selection = [val 1];
                v = struct;
                v.EventName = 'DoubleClicked';
                buttons(flisttab,v)
            case savefilebtn
                if isempty(ftab);return;end
                savefile;
            case delfilebtn
                if isempty(ftab);return;end
                deletefile;
            case playpause
                if isempty(ftab);return;end
                if h.Text == char(9205)
                    if progsld.Value == numframes;setframe(1);return;end
                    h.Text = char(9208);
                    scpts.Visible = 'on';
                    hcirc.Visible = 'off';
                    for i = 1:numdlcpts
                        roipts(i).Visible = 'off';
                    end
                    disptbl.Enable = 'off';
                    start(vtimer);
                else
                    stopfcn([]);
                end
            case stopbtn
                stopfcn(1);
            case nextframebtn
                setframe(fix+1);
            case prevframebtn
                setframe(fix-1)
            case spdbtn
                val = vtimer.UserData;
                vals = [1 2 5 10 50 100];
                ix = find(val == vals);
                if isempty(ix)|ix==length(vals)
                    val = 1;
                else
                    val = vals(ix+1);
                end
                vtimer.UserData = val;   
                h.Text = [num2str(val) 'x'];
            case stretchlimchk
                if strcmp(vtimer.Running,'on');return;end
                if h.Value
                    vidim.CData = imadjustn(read(vr,fix));
                else
                    vidim.CData = read(vr,fix);
                end
            case histviewbtn
                curval = find(strcmp(h.Text,h.UserData))+1;
                if curval==4;curval=1;end
                h.UserData{4}=curval;
                h.Text = h.UserData{curval};
                updatehist;
            otherwise
                if ismember(h,dlin) || ismember(h,zmlin)
                    val=round(e.IntersectionPoint(1));
                    setframe(val);
                elseif ismember(h,histpts) && e.Button==3
                    setnode(ptnodes(h==histpts));
                    [~,val] = min(pdist2(e.IntersectionPoint(1:2),[h.XData(:) h.YData(:)]));
                    setframe(val);
                end
        end
    end

    function stopfcn(ix)
        playpause.Text = char(9205);
        scpts.Visible = 'off';
        for i = 1:numdlcpts
            if showpts(i)
                roipts(i).Visible = 'on';
            end
        end
        disptbl.Enable = 'on';
        if ~isempty(ptstree.SelectedNodes)&&any(ptnodes==ptstree.SelectedNodes);
            hcirc.Visible = 'on';
        else
            hcirc.Visible = 'off';
        end
        stop(vtimer);
        if ~isempty(ix)
            setframe(ix);
        end
        scroll(disptbl,"row",progsld.Value);
    end

    function setframe(ix)
        isrunning = strcmp(vtimer.running,'on');
        if ix<1
            ix=1;
        elseif ix>numframes
            ix=numframes;
            if isrunning;buttons(playpause);end
        end
        fix = ix;
        if stretchlimchk.Value
            vidim.CData = imadjustn(read(vr,ix));
        else
            vidim.CData = read(vr,ix);
        end
        if isrunning
            scpts.XData = dtab{ix,1:3:numdlccols};
            scpts.YData = dtab{ix,2:3:numdlccols};
            scpts.XData(~showpts)=nan;
            scpts.YData(~showpts)=nan;
            updateskellines(find(showpts));
        else
            ctr = 1;
            for i = 1:numdlcpts
                pos  = dtab{ix,ctr:ctr+1};
                pos(isnan(pos))=-1;
                roipts(i).Position = pos;
                ctr = ctr+3;
            end
            updateskellines(find(showpts));
            scroll(disptbl,"row",ix);
            if ~isempty(ptstree.SelectedNodes)
                cix = find((ptnodes == ptstree.SelectedNodes));
                if ~isempty(cix)&xlut(cix)>0
                    if cix<numdlcpts
                        hcirc.XData = roipts(cix).Position(1);
                        hcirc.YData = roipts(cix).Position(2);
                    end
                    if ix>1 && ix<numframes
                        interpbtn.Enable = 'on';
                    else
                        interpbtn.Enable = 'off';
                    end
                    scroll(disptbl,"column",xlut(cix));
                    if dtab{ix,cix*3}==inf
                        revertbtn.Enable = 'on';
                    else
                        revertbtn.Enable = 'off';
                    end
                else
                    scroll(disptbl,"column",width(disptbl.Data));
                end
            end
        end
        xlim(zoomax,[ix-zmwind.Value/2 ix+zmwind.Value/2]);
        set(slds,'Value',ix);
        framewind.Value = "Frame "+string(fix)+" of "+string(numframes);
        drawnow limitrate
    end

    function refreshfilesavelabels
        removeStyle(flisttab);
        addStyle(flisttab,bluestyle,"row",find(ftabix == fileix));%highlight current file
        fss = ftab.isSave(ftabix);
        if ~isempty(fss)
            iix = find(fss);
            if ~isempty(iix)
                addStyle(flisttab,greenstyle,"cell",[iix(:) repmat(2,length(iix),1)]);
            end
            iix = find(~fss);
            if ~isempty(iix)
                addStyle(flisttab,redstyle,"cell",[iix(:) repmat(2,length(iix),1)]);
            end
        end
    end

    function loadvid(ix)
        if autosavechk.Value && isempty(fileix)
            savefile;
        end
        fileix = ix;
        %lock ui
        loadpanel.Visible = 'on';
        loadpanel.Title = 'Loading...';
        flisttab.Enable = 'off';
        nextfilebtn.Enable = 'off';
        prevfilebtn.Enable = 'off';
        savefilebtn.Enable = 'off';
        delfilebtn.Enable = 'off';
        autosavechk.Enable = 'off';drawnow
                
        %reset (some) ui appearance
        removeStyle(ptstree);
        removeStyle(ptslistL);
        removeStyle(ptslistR);
        removeStyle(disptbl);
        refreshfilesavelabels;
        
        DLCProof = [];
        if isfile(ftab.savename(fileix))
            load(ftab.savename(fileix));
        end

        %load data from CSV
        tname = ftab.csvname(ix);
        dtab = readtable(tname);
        dtab(:,1)=[];
        atab = [];

        varnames = readlines(tname);
        varnames = varnames(2);
        varnames = strsplit(varnames,',');
        varnames = varnames(2:end);
        ptslist = varnames(1:3:end);
        numdlcpts = length(ptslist);
        numdlccols = numdlcpts*3;
        for i = 1:length(varnames)
            switch mod(i,3)
                case 1
                    suf = " X";
                case 2
                    suf = " Y";
                case 0
                    suf = " P";
            end
            varnames(i) = varnames(i)+suf;
        end
        dtab.Properties.VariableNames = varnames;
        %ctab = original CSV data.
        %dtab = where we store corrected/labeled/processed stuff
        %databl = uitable that shows currently selected parts of dtab
        ctab = dtab;

        %FOLLOW THE BOUNCING BALL -> this is where we load the saved dtab
        if ~isempty(DLCProof)
            dtab = DLCProof.ProofreadCSV;
        end

        %setup display table
        ttab = dtab;
        ttab(:,3:3:end)=[];%don't show likelihood (use color code)
        xlut = 1:2:numdlcpts*2;
        ylut = 2:2:numdlcpts*2;
        ttab = [ttab table(repmat(string,[height(ttab) 1]),'VariableNames',{'Notes'})];
        disptbl.Data = ttab;
        disptbl.ColumnWidth = [repmat({'fit'},[1 width(ttab)-1]) {'auto'}];
        ed = false(1,width(dtab));
        ed(end)=true;
        disptbl.ColumnEditable = ed;
        removeStyle(disptbl);
        pmat = dtab{:,3:3:numdlccols}<.9;
        pmat = repelem(pmat,1,2);
        [rx,cx]=find(pmat);
        addStyle(disptbl,redstyle,"Cell",[rx,cx]);

        %video 
        vr = VideoReader(ftab.vidname(ix));
        hyp = sqrt(vr.Width^2 + vr.Height^2); %extend out to this to make sure "axis" lines always leave the image area
        vidaspect = vr.Height/vr.Width;
        xl = [0 vr.Width];
        yl = [0 vr.Height];
        numframes = vr.NumFrames;
        fix = 1;
        progax.XLim = [1 numframes];
        progsld.Value = 1;
        vidim.CData = read(vr,1);
        zmwind.Limits(2) = numframes;

        %initialize points lines and markers
        erec = [];
        vltempX =[];
        vltempY = [];
        for i = 1:numframes
            vltempX = [vltempX i i nan];
            vltempY = [vltempY nan 0 nan];
        end
        vllut = 1:3:numframes*3;
        set(goodbadlns,'XData',vltempX,'YData',vltempY,'ButtonDownFcn',@buttons,'HitTest','off');    
        set(goodbadrgn,'XData',1:numframes,'YData',nan(1,numframes),'ButtonDownFcn',@buttons,'HitTest','off');
        dselrgn.XData = [nan nan];
        zselrgn.XData = [nan nan];
        cols = lines(numel(ptslist));
        delete(histpts)
        histpts = [];
        for i =1:numdlcpts %separate loop so that these will all be "under" the ones plotted in next loop
            histpts = [histpts plot(vidax,dtab{:,i*3-2},dtab{:,i*3-1},'.','MarkerEdgeColor',cols(i,:),'ButtonDownFcn',@buttons)];
        end
        delete(scpts);
        scpts = scatter(vidax,nan(size(ptslist)),nan(size(ptslist)),50,cols,'filled','Visible','off','MarkerEdgeColor','k');
        delete(roipts);
        roipts = [];
        delete(ptnodes);
        ptnodes = [];
        delete(lnnodes)
        lnnodes = [];
        delete(marknodes)
        marknodes=[];
        delete(zmlin);
        zmlin = [];
        delete(dlin);
        dlin = [];
        delete(zanglin);
        zanglin = [];
        delete(danglin);
        danglin = [];

        %initialize skeleton items in tab
        skellist = ["DLC Points" ptslist "Fixed Points" "Lines and Angles"];
        ptslistL.Items = skellist;
        ptslistR.Items = skellist;

        skeldat = struct;
        skeldat(1).Tag = 'Root';
        skeldat(numdlcpts+2).Tag = 'Root';
        skeldat(numdlcpts+3).Tag = 'Root';
        skeldat(1).color = [0 0 0];
        skeldat(numdlcpts+2).color = [0 0 0];
        skeldat(numdlcpts+3).color = [0 0 0];
        skeldat(1).origcolor = [0 0 0];
        skeldat(numdlcpts+2).origcolor = [0 0 0];
        skeldat(numdlcpts+3).origcolor = [0 0 0];
        skeldat(1).name = "DLC Points";
        skeldat(1).csvname = "DLC Points";
        skeldat(numdlcpts+2).name = "Fixed Points";
        skeldat(numdlcpts+2).csvname = "Fixed Points";
        skeldat(numdlcpts+3).name = "Lines and Angles";
        skeldat(numdlcpts+3).csvname = "Lines and Angles";
               
        addStyle(ptslistL,boldstyle,"item",[1 numdlcpts+2 numdlcpts+3])
        addStyle(ptslistR,boldstyle,"item",[1 numdlcpts+2 numdlcpts+3])

        zx = [];
        zy = [];
        dx = [];
        dy = [];
        for i = 1:numdlcpts
            udat = struct;
            udat.ix = i;
            udat.memberlines = [];
            udat.memberlineix = [];
            udat.memberlinetype = [];
            udat.memberlinepartner = [];
            roipts = [roipts; images.roi.Point(vidax,'Color',cols(i,:),'Label',ptslist(i),'ContextMenu',[],'Deletable',false,'LabelVisible',labvis,'UserData',udat,'Position',[-1 -1])];
            addlistener(roipts(end),'ROIClicked',@ptcb);
            addlistener(roipts(end),'MovingROI',@ptcb);
            addlistener(roipts(end),'ROIMoved',@ptcb);
            ptnodes = [ptnodes; uitreenode(dlcroot,'Text',ptslist(i),'NodeData',i,'Tag',"DLC",'UserData',cols(i,:))];
            ico = cat(3,cols(i,1),cols(i,2),cols(i,3));
            tstyle = uistyle("Icon",ico);
            addStyle(ptstree,tstyle,"node",ptnodes(end));
            addStyle(ptslistL,tstyle,"item",i+1);
            addStyle(ptslistR,tstyle,"item",i+1);
            skeldat(i+1).Tag = "DLC";
            skeldat(i+1).color = cols(i,:);
            skeldat(i+1).origcolor = cols(i,:);
            skeldat(i+1).name = ptslist(i);
            skeldat(i+1).csvname = ptslist(i);
            yyaxis(datax,'left');
            yyaxis(zoomax,'left');
            zx = [zx; lineAlphaFcn(zoomax,1:numframes,dtab{:,i*3-2},cols(i,:),.2,'ButtonDownFcn',@buttons)];
            zy = [zy; lineAlphaFcn(zoomax,1:numframes,dtab{:,i*3-1},cols(i,:),.2,'LineStyle','-.','ButtonDownFcn',@buttons)];
            dx = [dx; lineAlphaFcn(datax,1:numframes,dtab{:,i*3-2},cols(i,:),.1,'ButtonDownFcn',@buttons)];
            dy = [dy; lineAlphaFcn(datax,1:numframes,dtab{:,i*3-1},cols(i,:),.1,'LineStyle','-.','ButtonDownFcn',@buttons)];
        end
        ptslistL.ItemsData = skeldat;
        ptslistR.ItemsData = skeldat;
        zmlin = [zx zy];
        dlin = [dx dy];
        ptstree.CheckedNodes = ptstree.Children;
        expand(dlcroot);
        
        delete(skellns)
        skellns = [];
        delete(marklns)
        marklns = [];
        markshort = [];
        marksymb = [];
        markcol = [];
        marktab.Data=etab;

        defconf=[];
        nnet = string(ftab.netname(fileix));
        nix = find(strcmp(nnet,defnetset.Network));
        if ~isempty(nix)
            defconf = defnetset.Config(nix);
            resetnetbtn.Enable='on';
        else
            resetnetbtn.Enable='off';
        end

        %NOW we load the skeleton and events and stuff
        if ~isempty(DLCProof)
            importconfig(DLCProof.Configuration)
            evts = DLCProof.Events;
            for i = 1:length(evts)
                idx = evts(i).FrameIndex;
                marklns(i,5).YData(idx)=1;
                marklns(i,6).YData(idx)=1;
                val = ~isnan(marklns(i,6).YData);
                val = diff([false;val(:)]);
                mark = false(size(val));                
                mark(val==1)=true;
                mark(val(2:end)==-1)=true;

                marklns(i,1).YData(vllut(mark))=1;
                marklns(i,2).YData(vllut(mark))=1;
                marklns(i,1).YData(vllut(~mark))=nan;
                marklns(i,2).YData(vllut(~mark))=nan;

                marklns(i,3).YData(val(2:end)==-1)=0;
                marklns(i,4).YData(val(2:end)==-1)=0;
                marklns(i,3).YData(val==1)=1;
                marklns(i,4).YData(val==1)=1;
                marklns(i,3).YData(~mark)=nan;
                marklns(i,4).YData(~mark)=nan;
                erec(i).FrameIndex = idx;
            end
            disptbl.Data.Notes = DLCProof.FrameNotes;

            uiset = DLCProof.UISettings;
            if isfield(uiset,'curframe')
                fix = uiset.curframe;
            end
            if isfield(uiset,'showhist')
                histviewbtn.UserData = uiset.showhist;
                histviewbtn.Text = uiset.showhist{uiset.showhist{4}};
            end
            if isfield(uiset,'frameskip')
                vtimer.UserData = uiset.frameskip;
                spdbtn.Text = string(uiset.frameskip)+"x";
            end
            if isfield(uiset,'stretchhist')
                stretchlimchk.Value=uiset.stretchhist;
            end
            if isfield(uiset,'windsize')
                zmwind.Value = uiset.windsize;
            end
            if isfield(uiset,'XLim')
                xl = uiset.XLim;
            end
            if isfield(uiset,'YLim')
                yl = uiset.YLim;
            end
        elseif ~isempty(defconf)
            importconfig(defconf);
        end

        n = struct;
        n.EventName='CheckedNodesChanged';
        nodecb(ptstree,n)
        refreshpts;

        restackhandles();

        datax.XLim = [1 numframes];
        xlim(vidax,xl);
        ylim(vidax,yl);
        resize(f,[]);
        setframe(fix);

        loadpanel.Title = '';
        loadpanel.Visible = 'off';
        flisttab.Enable = 'on';
        nextfilebtn.Enable = 'on';
        prevfilebtn.Enable = 'on';
        savefilebtn.Enable = 'on';
        delfilebtn.Enable = 'on';
        autosavechk.Enable = 'on';drawnow
    end

    function [flist, networks] = getfiles(searchdir)
        networks = {};
        files = dir([searchdir filesep '**' filesep '*DLC_resnet*.csv']);
        flist = table;
        for i = 1:length(files)
            csvname = fullfile(files(i).folder,files(i).name);
            ix = strfind(upper(csvname),'DLC_RESNET');
            ix = ix(end)-1;
            vidname = csvname(1:ix);
            savename = strcat(csvname(1:end-4),'_PROOF.mat');
            netname = csvname(ix+1:end-4);
            dispname = strsplit(vidname,filesep);
            dispname = strcat(dispname{end-1},filesep,dispname{end});
            if isfile([vidname '.avi'])
                vidname = [vidname '.avi'];
            elseif isfile([vidname '.mp4'])
                vidname = [vidname '.mp4'];
            else
                continue
            end
            netname =string(netname);
            dispname = string(dispname);
            vidname = string(vidname);
            csvname = string(csvname);
            savename = string(savename);
            isSave = isfile(savename);
            if isSave
                note=matfile(savename);
                note = note.DLCProof;
                filenote = string(note.FileNote);
            else
                filenote = "";
            end
            flist = [flist; table(dispname,csvname,vidname,netname,savename,isSave,filenote)];
        end
        if ~isempty(flist)
            networks = unique(flist.netname);
        end
    end

    function zmcb(h,e)
        switch h
            case zmbtn
                if zmbtn.Value
                    zoom(vidax,'on');
                else
                    zoom(vidax,'off');
                end
                if pnbtn.Value
                    pan(vidax,'off');
                    pnbtn.Value = false;
                end
            case pnbtn
                if pnbtn.Value
                    pan(vidax,'on');
                else
                    pan(vidax,'off');
                end
                if zmbtn.Value
                    zoom(vidax,'off');
                    zmbtn.Value = false;
                end
            case hmbtn
                if zmbtn.Value
                    zoom(vidax,'off');
                    zmbtn.Value = false;
                end
                if pnbtn.Value
                    pan(vidax,'off');
                    pnbtn.Value = false;
                end
                zoom(vidax,'out');
                xlim(vidax,[0 vr.Width]);
                ylim(vidax,[0 vr.Height]);
        end
    end

    function keyshort(h,e)
        key = e.Key;
        if contains(key,'numpad');key = e.Character;end
        switch key
            case markshort
                ix = find(strcmp(key,markshort));
                if ~all(isnan(dselrgn.XData))
                    markframe(ix,dselrgn.XData(1):dselrgn.XData(2));
                else
                    markframe(ix);
                end
                % markframe(ix);
            case 'leftbracket'
                buttons(selstartbtn,[]);
            case 'rightbracket'
                buttons(selstopbtn,[]);
            case 'backslash'
                buttons(selresetbtn,[]);
            case {'leftarrow','a'}                
                if contains(e.Modifier,'control')
                    goodix=goodbadlns(1).XData(find(goodbadlns(1).YData==1));
                    badix=goodbadlns(2).XData(find(goodbadlns(2).YData==1));
                    eix = [];
                    if ~isempty(showmarks)
                        for i = find(showmarks(:)')
                            eix = [eix find(~isnan(marklns(i,3).YData))];
                        end
                    end
                    ix = unique([goodix badix eix]);
                    ix = ix(ix<fix);
                    if isempty(ix)
                        setframe(1);
                    else
                        setframe(ix(end));
                    end
                else
                    setframe(progsld.Value-1)
                end
            case {'rightarrow', 'd'}
                if contains(e.Modifier,'control')
                    goodix=goodbadlns(1).XData(find(goodbadlns(1).YData==1));
                    badix=goodbadlns(2).XData(find(goodbadlns(2).YData==1));
                    eix = [];
                    if ~isempty(showmarks)
                        for i = find(showmarks(:)')
                            eix = [eix find(~isnan(marklns(i,3).YData))];
                        end
                    end
                    ix = unique([goodix badix eix]);
                    ix = ix(ix>fix);
                    if isempty(ix)
                        setframe(numframes);
                    else
                        setframe(ix(1));
                    end
                else
                    setframe(progsld.Value+1)
                end
            case {'uparrow','downarrow','w','s'}
                allnodes = [ptnodes(:)' lnnodes(:)' marknodes(:)'];
                if isempty(ptstree.SelectedNodes)
                    ix =[];
                else
                    ix= find(ptstree.SelectedNodes == allnodes);
                end
                switch e.Key
                    case {'uparrow','w'}
                        if isempty(ix);ix=length(allnodes)+1;end
                        ix = ix-1;
                        if ix<1;focus(f);return;end
                    case {'downarrow','s'}
                        if isempty(ix);ix=0;end
                        ix = ix+1;
                        if ix>length(allnodes);focus(f);return;end
                end
                ptstree.SelectedNodes =  allnodes(ix);
                n = struct;
                n.EventName = 'SelectionChanged';
                nodecb(ptstree,n);
            case 'space'
                buttons(playpause);
            case 'i'
                buttons(interpbtn);
        end
        focus(f);
    end
end