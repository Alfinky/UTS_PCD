function ImageProcessingGUI
% IMAGEPROCESSINGGUI (versi grid & callback fix)
% - Konvolusi custom (tanpa conv/conv2 pada fungsi inti) + compare conv2
% - Smoothing spasial (mean & gaussian) via konvolusi custom
% - LP/HP di ranah frekuensi: ILPF/GLPF/BLPF + IHPF/GHPF/BHPF
% - Homomorphic brightening
% - Noise (salt&pepper, gaussian) + 9 metode denoise (tanpa medfilt2)
% - Periodic noise removal (auto notch)
% - Motion blur + Wiener deconvolution (tanpa fungsi Wiener bawaan)
% - Layout responsif (uigridlayout), kontrol rapi & scrollable
%
% Jalankan: ImageProcessingGUI

%% ======================= State =======================
state.I = [];   % original
state.J = [];   % processed cache
state.padMode = 'replicate';
state.mask = ones(3)/9;
state.sigma = 1.0;
state.lpCutoff = 30;
state.order = 2;
state.bright_lowGain = 0.75;
state.bright_highGain = 1.5;
state.bright_cutoff = 30;
state.bright_order = 2;
state.noise.sp = 0.05;
state.noise.gaussMean = 0;
state.noise.gaussVar = 0.01;
state.contraQ = 1.5;

%% ======================= UI: Root ====================
fig = uifigure('Name','Image Processing GUI','Position',[80 50 1400 850]);

% Grid utama 2x2: [controls | top images; controls | log]
mainGrid = uigridlayout(fig,[2 2]);
mainGrid.RowHeight   = {'1x', 300};
mainGrid.ColumnWidth = {500, '1x'};

% Panel kiri: Controls (scrollable)
pLeft = uipanel(mainGrid,'Title','Controls','FontWeight','bold');
pLeft.Layout.Row = [1 2];
pLeft.Layout.Column = 1;
pLeft.Scrollable = 'on';

% Panel kanan atas: Original | Processed
rightTop = uigridlayout(mainGrid,[1 2]);
rightTop.Layout.Row = 1; rightTop.Layout.Column = 2;
rightTop.ColumnWidth = {'1x','1x'};

pMid = uipanel(rightTop,'Title','Original','FontWeight','bold');  pMid.Layout.Column = 1;
pRight = uipanel(rightTop,'Title','Processed','FontWeight','bold'); pRight.Layout.Column = 2;

axIn  = uiaxes(uigridlayout(pMid,[1 1]));  title(axIn,'Input');  axis(axIn,'image');  axIn.XTick=[]; axIn.YTick=[];
axOut = uiaxes(uigridlayout(pRight,[1 1])); title(axOut,'Output'); axis(axOut,'image'); axOut.XTick=[]; axOut.YTick=[];

% Panel kanan bawah: log
pLog = uipanel(mainGrid,'Title','Info / Log','FontWeight','bold');
pLog.Layout.Row = 2; pLog.Layout.Column = 2;
txtLog = uitextarea(uigridlayout(pLog,[1 1]),'Editable','off');

% Grid kolom kiri berisi beberapa sub-panel (tiap seksi satu panel)
leftGrid = uigridlayout(pLeft,[10 1]);
leftGrid.RowHeight = {'fit','fit','fit','fit','fit','fit','fit','fit','fit','fit'};
leftGrid.Padding = [10 10 10 10];
leftGrid.RowSpacing = 12;

%% ============== 1) File =====================
sec1 = uipanel(leftGrid,'Title','1) File');
g1 = uigridlayout(sec1,[1 3]); g1.ColumnWidth = {150,100,'1x'};
btnLoad = uibutton(g1,'Text','Load Image...'); btnLoad.ButtonPushedFcn = @onLoad;
btnReset = uibutton(g1,'Text','Reset');        btnReset.ButtonPushedFcn = @onReset;

%% ============== 2) Custom Convolution =========
sec2 = uipanel(leftGrid,'Title','2) Custom Convolution (no conv2)');
g2 = uigridlayout(sec2,[5 3]);
g2.RowHeight   = {24, 180, 30, 30, 30};
g2.ColumnWidth = {120,120,'1x'};

uilabel(g2,'Text','Mask size n:','HorizontalAlignment','right');
edN = uieditfield(g2,'numeric','Value',3,'RoundFractionalValues','on'); edN.Limits=[1 Inf];
uibutton(g2,'Text','Set Mean Kernel','ButtonPushedFcn',@onSetMean);

maskTable = uitable(g2); maskTable.Layout.Row=2; maskTable.Layout.Column=[1 3];
maskTable.ColumnEditable = true; maskTable.RowName = []; maskTable.ColumnName = [];

uilabel(g2,'Text',''); % spacer
btnBuildMask = uibutton(g2,'Text','Build n×n Table'); btnBuildMask.ButtonPushedFcn = @onBuildMask;
uilabel(g2,'Text',''); % spacer

uilabel(g2,'Text','Padding:','HorizontalAlignment','right');
padDrop = uidropdown(g2,'Items',{'replicate','zero'},'Value','replicate'); 
btnApplyConv = uibutton(g2,'Text','Apply Custom Convolution'); btnApplyConv.ButtonPushedFcn = @onApplyCustomConv;

uilabel(g2,'Text',''); 
uilabel(g2,'Text',''); 
btnCompareConv = uibutton(g2,'Text','Compare with conv2'); btnCompareConv.ButtonPushedFcn = @onCompareWithConv2;

%% ============== 3) Spatial Smoothing =========
sec3 = uipanel(leftGrid,'Title','3) Spatial Smoothing (uses custom conv)');
g3 = uigridlayout(sec3,[2 5]); g3.RowHeight={24,30}; g3.ColumnWidth={70,60,100,60,'1x'};
uilabel(g3,'Text','n (odd):','HorizontalAlignment','right');
edNSmooth = uieditfield(g3,'numeric','Value',3,'RoundFractionalValues','on');
uilabel(g3,'Text','Gaussian σ:','HorizontalAlignment','right');
edSigma = uieditfield(g3,'numeric','Value',1.0);
uilabel(g3,'Text','');  % spacer
btnMean = uibutton(g3,'Text','Mean Filter');   btnMean.Layout.Column=[1 2]; btnMean.ButtonPushedFcn = @onMean;
btnGauss= uibutton(g3,'Text','Gaussian Filter'); btnGauss.Layout.Column=[3 4]; btnGauss.ButtonPushedFcn = @onGauss;

%% ============== 4) Frequency Filters LP/HP ====
sec4 = uipanel(leftGrid,'Title','4) Frequency Filters (LP/HP)');
g4 = uigridlayout(sec4,[3 6]); g4.RowHeight={24,30,30};
g4.ColumnWidth={70,70,70,70,70,70};
uilabel(g4,'Text','Cutoff D0:','HorizontalAlignment','right');
edD0 = uieditfield(g4,'numeric','Value',30);
uilabel(g4,'Text','Order n:','HorizontalAlignment','right');
edOrder = uieditfield(g4,'numeric','Value',2);
uilabel(g4,'Text',''); uilabel(g4,'Text',''); % fillers
uibutton(g4,'Text','ILPF','ButtonPushedFcn',@(s,e)onFreq('ILPF'));
uibutton(g4,'Text','GLPF','ButtonPushedFcn',@(s,e)onFreq('GLPF'));
uibutton(g4,'Text','BLPF','ButtonPushedFcn',@(s,e)onFreq('BLPF'));
uibutton(g4,'Text','IHPF','ButtonPushedFcn',@(s,e)onFreq('IHPF'));
uibutton(g4,'Text','GHPF','ButtonPushedFcn',@(s,e)onFreq('GHPF'));
uibutton(g4,'Text','BHPF','ButtonPushedFcn',@(s,e)onFreq('BHPF'));

%% ============== 5) Homomorphic Brightening =====
sec5 = uipanel(leftGrid,'Title','5) Brighten (Homomorphic Filter)');
g5 = uigridlayout(sec5,[3 6]); g5.RowHeight={24,24,30}; g5.ColumnWidth={70,70,80,70,70,'1x'};
uilabel(g5,'Text','γ_low (<=1):','HorizontalAlignment','right');
edLow = uieditfield(g5,'numeric','Value',state.bright_lowGain);
uilabel(g5,'Text','γ_high (>1):','HorizontalAlignment','right');
edHigh = uieditfield(g5,'numeric','Value',state.bright_highGain);
uilabel(g5,'Text',''); uilabel(g5,'Text','');

uilabel(g5,'Text','cutoff D0:','HorizontalAlignment','right');
edBcut = uieditfield(g5,'numeric','Value',state.bright_cutoff);
uilabel(g5,'Text','order n:','HorizontalAlignment','right');
edBord = uieditfield(g5,'numeric','Value',state.bright_order);
uilabel(g5,'Text',''); uilabel(g5,'Text','');

btnBright = uibutton(g5,'Text','Apply Homomorphic'); btnBright.Layout.Row=3; btnBright.Layout.Column=[1 3];
btnBright.ButtonPushedFcn = @onBright;

%% ============== 6) Noise & Denoise (rapi grid) ==
sec6 = uipanel(leftGrid,'Title','6) Noise & Denoise');
g6 = uigridlayout(sec6,[3 6]); g6.RowHeight={28,32,32}; g6.ColumnWidth={60,80,80,80,150,'1x'};

lblSP = uilabel(g6,'Text','S&P p:','HorizontalAlignment','right'); lblSP.Layout.Row=1; lblSP.Layout.Column=1;
edSP = uieditfield(g6,'numeric','Value',state.noise.sp); edSP.Layout.Row=1; edSP.Layout.Column=2;
lblGM = uilabel(g6,'Text','G μ:','HorizontalAlignment','right'); lblGM.Layout.Row=1; lblGM.Layout.Column=3;
edGM = uieditfield(g6,'numeric','Value',state.noise.gaussMean); edGM.Layout.Row=1; edGM.Layout.Column=4;
lblGV = uilabel(g6,'Text','G var:','HorizontalAlignment','right'); lblGV.Layout.Row=1; lblGV.Layout.Column=5;
edGV = uieditfield(g6,'numeric','Value',state.noise.gaussVar); edGV.Layout.Row=1; edGV.Layout.Column=6;

btnAddSP = uibutton(g6,'Text','Add S&P'); btnAddSP.Layout.Row=2; btnAddSP.Layout.Column=1; btnAddSP.ButtonPushedFcn=@onAddSP;
btnAddG  = uibutton(g6,'Text','Add Gaussian'); btnAddG.Layout.Row=2; btnAddG.Layout.Column=2; btnAddG.ButtonPushedFcn=@onAddG;
lblDen = uilabel(g6,'Text','Denoise:','HorizontalAlignment','right'); lblDen.Layout.Row=2; lblDen.Layout.Column=3;
dropDenoise = uidropdown(g6,'Items',{'min','max','median (custom)','arithmetic mean','geometric mean','harmonic mean','contraharmonic mean','midpoint','alpha-trimmed'},'Value','median (custom)');
dropDenoise.Layout.Row=2; dropDenoise.Layout.Column=[4 5];
lblQd = uilabel(g6,'Text','Q/d:','HorizontalAlignment','right'); lblQd.Layout.Row=2; lblQd.Layout.Column=6;
edQd = uieditfield(g6,'numeric','Value',state.contraQ); edQd.Layout.Row=2; edQd.Layout.Column=6;

btnApplyDenoise = uibutton(g6,'Text','Apply'); btnApplyDenoise.Layout.Row=3; btnApplyDenoise.Layout.Column=[4 5];
btnApplyDenoise.ButtonPushedFcn = @onApplyDenoise;

%% ============== 7) Motion Blur / Wiener & Periodic Noise ==
sec7 = uipanel(leftGrid,'Title','7) Motion Blur & Wiener; 6) Periodic Noise');
g7 = uigridlayout(sec7,[3 8]); g7.RowHeight={24,30,30}; g7.ColumnWidth={40,60,50,70,60,70,70,'1x'};
% Row 1: motion params
uilabel(g7,'Text','Len:','HorizontalAlignment','right'); edLen = uieditfield(g7,'numeric','Value',15);
uilabel(g7,'Text','Angle:','HorizontalAlignment','right'); edTheta = uieditfield(g7,'numeric','Value',0);
btnMotion = uibutton(g7,'Text','Apply Motion Blur'); btnMotion.Layout.Column=[5 7]; btnMotion.ButtonPushedFcn = @onMotionBlur;
% Row 2: Wiener
uilabel(g7,'Text','K:','HorizontalAlignment','right'); edWk = uieditfield(g7,'numeric','Value',0.005); edWk.Layout.Row=2; edWk.Layout.Column=2;
btnWiener = uibutton(g7,'Text','Wiener Deconv'); btnWiener.Layout.Row=2; btnWiener.Layout.Column=[3 5]; btnWiener.ButtonPushedFcn = @onWiener;
% Row 3: periodic notch
uilabel(g7,'Text','#pairs:','HorizontalAlignment','right'); edNPairs = uieditfield(g7,'numeric','Value',4); edNPairs.Layout.Row=3; edNPairs.Layout.Column=2;
uilabel(g7,'Text','σ:','HorizontalAlignment','right'); edNotch = uieditfield(g7,'numeric','Value',10); edNotch.Layout.Row=3; edNotch.Layout.Column=4;
btnNotch = uibutton(g7,'Text','Auto Notch Remove'); btnNotch.Layout.Row=3; btnNotch.Layout.Column=[5 7]; btnNotch.ButtonPushedFcn=@onPeriodicNotch;

%% ================= Utility: log ======================
    function logMsg(s)
        txtLog.Value = [string(datetime('now')) + ": " + s; txtLog.Value];
    end

%% ================== Callbacks ========================
    function onLoad(~,~)
        try
            [f,p] = uigetfile({'*.*','All Files'},'Choose an image');
            if isequal(f,0); return; end
            I = imread(fullfile(p,f));
            if isa(I,'uint16'); I = uint8(double(I)/65535*255); end
            state.I = I; imshow(state.I,'Parent',axIn); axIn.Title.String='Input';
            state.J = []; cla(axOut); title(axOut,'Output');
            logMsg(sprintf('Loaded: %s',f));
        catch ME
            logMsg(['Load error: ' ME.message]);
        end
    end

    function onReset(~,~)
        if ~isempty(state.I)
            imshow(state.I,'Parent',axIn); axIn.Title.String='Input';
        end
        state.J=[]; cla(axOut); title(axOut,'Output'); logMsg('Reset view.');
    end

    function onBuildMask(~,~)
        n = max(1,round(edN.Value)); if mod(n,2)==0, n=n+1; end
        maskTable.Data = zeros(n); maskTable.ColumnName=repmat({''},1,n); maskTable.RowName=[];
        logMsg(sprintf('Created %dx%d kernel table.',n,n));
    end

    function onSetMean(~,~)
        data = maskTable.Data; if isempty(data); onBuildMask(); data=maskTable.Data; end
        n = size(data,1); maskTable.Data = ones(n)/n^2; logMsg(sprintf('Set mean kernel %dx%d.',n,n));
    end

    function onApplyCustomConv(~,~)
        if isempty(state.I), logMsg('Load an image first.'); return; end
        if isempty(maskTable.Data), logMsg('Build or set a kernel first.'); return; end
        K = double(maskTable.Data); state.padMode = padDrop.Value;
        J = applyPerChannel(state.I,@(ch) myConv2(ch,K,state.padMode));
        state.J = J; imshow(state.J,'Parent',axOut); title(axOut,'Custom Convolution'); logMsg('Custom convolution applied.');
    end

    function onCompareWithConv2(~,~)
        if isempty(state.I), logMsg('Load an image first.'); return; end
        if isempty(maskTable.Data), logMsg('Build or set a kernel first.'); return; end
        K = double(maskTable.Data);
        A = im2double(state.I);
        J1 = applyPerChannel(A,@(ch) myConv2(ch,K,padDrop.Value));
        J2 = applyPerChannel(A,@(ch) conv2padCompare(ch,K,padDrop.Value));
        diffImg = im2uint8(mat2gray(abs(J1-J2)));
        montage({im2uint8(J1),im2uint8(J2),diffImg},'Parent',axOut);
        title(axOut,'[Custom | conv2-based | abs diff]');
        logMsg(sprintf('Compared custom vs conv2. Mean abs diff: %.6f',mean(abs(J1(:)-J2(:)))));
    end

    function onMean(~,~)
        if isempty(state.I), logMsg('Load an image first.'); return; end
        n = max(1,round(edNSmooth.Value)); if mod(n,2)==0, n=n+1; end
        K = ones(n)/(n*n);
        J = applyPerChannel(state.I,@(ch) myConv2(ch,K,padDrop.Value));
        state.J = J; imshow(state.J,'Parent',axOut); title(axOut,sprintf('Mean %dx%d',n,n));
    end

    function onGauss(~,~)
        if isempty(state.I), logMsg('Load an image first.'); return; end
        n = max(1,round(edNSmooth.Value)); if mod(n,2)==0, n=n+1; end
        sigma = max(0.1,edSigma.Value);
        K = gaussianKernel(n,sigma);
        J = applyPerChannel(state.I,@(ch) myConv2(ch,K,padDrop.Value));
        state.J = J; imshow(state.J,'Parent',axOut); title(axOut,sprintf('Gaussian %dx%d (\\sigma=%.2f)',n,sigma));
    end

    function onFreq(kind)
        if isempty(state.I), logMsg('Load an image first.'); return; end
        D0 = max(1,edD0.Value); n = max(1,round(edOrder.Value));
        J = applyPerChannel(state.I,@(ch) freqFilter2D(ch,kind,D0,n));
        state.J = J; imshow(state.J,'Parent',axOut); title(axOut,kind);
    end

    function onBright(~,~)
        if isempty(state.I), logMsg('Load an image first.'); return; end
        gl=max(0.1,edLow.Value); gh=max(1.01,edHigh.Value); D0=max(1,edBcut.Value); n=max(1,round(edBord.Value));
        J = applyPerChannel(state.I,@(ch) homomorphicBrighten(ch,gl,gh,D0,n));
        state.J = J; imshow(state.J,'Parent',axOut); title(axOut,sprintf('Homomorphic (\\gamma_l=%.2f, \\gamma_h=%.2f)',gl,gh));
    end

    function onAddSP(~,~)
        if isempty(state.I), logMsg('Load an image first.'); return; end
        p = min(max(edSP.Value,0),1);
        J = addSaltPepper(state.I,p);
        state.J = J; imshow(state.J,'Parent',axOut); title(axOut,sprintf('S&P noise (p=%.2f)',p));
    end

    function onAddG(~,~)
        if isempty(state.I), logMsg('Load an image first.'); return; end
        mu = edGM.Value; v=max(edGV.Value,1e-6);
        J = addGaussianNoise(state.I,mu,v);
        state.J = J; imshow(state.J,'Parent',axOut); title(axOut,sprintf('Gaussian noise (\\mu=%.2f, var=%.4f)',mu,v));
    end

    function onApplyDenoise(~,~)
        if isempty(state.I) && isempty(state.J), logMsg('Load an image first.'); return; end
        src = state.J; if isempty(src), src = state.I; end
        choice = dropDenoise.Value; Qd = edQd.Value;
        n = max(3, round(edNSmooth.Value)); if mod(n,2)==0, n=n+1; end
        switch choice
            case 'min',      fn = @(ch) orderFilter2D(ch,n,1,'min');
            case 'max',      fn = @(ch) orderFilter2D(ch,n,1,'max');
            case 'median (custom)', fn = @(ch) medianFilter2D(ch,n);
            case 'arithmetic mean', fn = @(ch) myConv2(ch,ones(n)/(n*n),padDrop.Value);
            case 'geometric mean',  fn = @(ch) geometricMeanFilter2D(ch,n);
            case 'harmonic mean',   fn = @(ch) harmonicMeanFilter2D(ch,n);
            case 'contraharmonic mean', fn = @(ch) contraharmonicMeanFilter2D(ch,n,Qd);
            case 'midpoint',   fn = @(ch) midpointFilter2D(ch,n);
            case 'alpha-trimmed', d=max(0,round(Qd)); fn = @(ch) alphaTrimmedMeanFilter2D(ch,n,d);
            otherwise, logMsg('Unknown denoise filter.'); return;
        end
        J = applyPerChannel(src,fn);
        state.J = J; imshow(state.J,'Parent',axOut); title(axOut,[choice ' (n=' num2str(n) ')']);
    end

    function onMotionBlur(~,~)
        if isempty(state.I), logMsg('Load an image first.'); return; end
        L=max(1,round(edLen.Value)); th=edTheta.Value; PSF=makeMotionPSF(L,th);
        J = applyPerChannel(state.I,@(ch) myConv2(ch,PSF,padDrop.Value));
        state.J=J; imshow(state.J,'Parent',axOut); title(axOut,sprintf('Motion blur (L=%d, \\theta=%.1f°)',L,th));
    end

    function onWiener(~,~)
        if isempty(state.I) && isempty(state.J), logMsg('Load or blur an image first.'); return; end
        L=max(1,round(edLen.Value)); th=edTheta.Value; K=max(0,edWk.Value); PSF=makeMotionPSF(L,th);
        src = state.J; if isempty(src), src=state.I; end
        J = applyPerChannel(src,@(ch) wienerDeconv2D(ch,PSF,K));
        state.J=J; imshow(state.J,'Parent',axOut); title(axOut,sprintf('Wiener (L=%d, \\theta=%.1f°, K=%.4f)',L,th,K));
    end

    function onPeriodicNotch(~,~)
        if isempty(state.I) && isempty(state.J), logMsg('Load an image first.'); return; end
        src = state.J; if isempty(src), src=state.I; end
        pairs=max(1,round(edNPairs.Value)); sig=max(1,edNotch.Value);
        J = applyPerChannel(src,@(ch) autoNotchDenoise(ch,pairs,sig));
        state.J=J; imshow(state.J,'Parent',axOut); title(axOut,sprintf('Periodic noise removal (pairs=%d, σ=%.1f)',pairs,sig));
    end

%% =================== Core Ops & Helpers ===================
function J = applyPerChannel(I, fun)
    A = im2double(I);
    if size(A,3)==1
        B = fun(A);
        J = im2uint8(mat2gray(B));
    else
        B = zeros(size(A));
        for c=1:3, B(:,:,c) = fun(A(:,:,c)); end
        J = im2uint8(mat2gray(B));
    end
end

function out = myConv2(img, kernel, padMode)  % konvolusi manual
    img = double(img); K = double(kernel); K = rot90(K,2);
    [m,n] = size(img); [p,q] = size(K); r=floor(p/2); s=floor(q/2);
    if strcmpi(padMode,'replicate'), P = padReplicate(img,r,s); else, P = padZero(img,r,s); end
    out = zeros(m,n);
    for i=1:m
        for j=1:n
            region = P(i:i+2*r, j:j+2*s);
            out(i,j) = sum(region(:).*K(:));
        end
    end
end

function P = padZero(A,r,s)
    [m,n] = size(A); P=zeros(m+2*r,n+2*s); P(1+r:end-r,1+s:end-s)=A;
end

function P = padReplicate(A,r,s)
    [m,n] = size(A); P=zeros(m+2*r,n+2*s); P(1+r:end-r,1+s:end-s)=A;
    P(1:r,1+s:end-s)=repmat(A(1,:),r,1); P(end-r+1:end,1+s:end-s)=repmat(A(end,:),r,1);
    P(:,1:s)=repmat(P(:,s+1),1,s); P(:,end-s+1:end)=repmat(P(:,end-s),1,s);
end

function out = conv2padCompare(img,K,padMode)
    [r,s]=deal(floor(size(K,1)/2),floor(size(K,2)/2));
    if strcmpi(padMode,'replicate'), P = padReplicate(img,r,s); else, P = padZero(img,r,s); end
    out = conv2(P, rot90(K,2), 'valid');
end

function G = gaussianKernel(n,sigma)
    c=(n-1)/2; [x,y]=meshgrid(-c:c,-c:c);
    G=exp(-(x.^2+y.^2)/(2*sigma^2)); G=G/sum(G(:));
end

function out = freqFilter2D(img,kind,D0,n)
    A=double(img); [M,N]=size(A);
    F=fftshift(fft2(A));
    [U,V]=meshgrid((-floor(N/2)):(ceil(N/2)-1), (-floor(M/2)):(ceil(M/2)-1));
    D=sqrt(U.^2+V.^2);
    switch upper(kind)
        case 'ILPF', H=double(D<=D0);
        case 'GLPF', H=exp(-(D.^2)/(2*D0^2));
        case 'BLPF', H=1./(1+(D./D0).^(2*n));
        case 'IHPF', H=double(D>D0);
        case 'GHPF', H=1-exp(-(D.^2)/(2*D0^2));
        case 'BHPF', H=1./(1+(D0./max(D,eps)).^(2*n));
        otherwise, H=ones(M,N);
    end
    out = real(ifft2(ifftshift(F.*H)));
end

function out = homomorphicBrighten(img,gl,gh,D0,n)
    I=im2double(img); I(I<=0)=1e-6; lnI=log(I);
    F=fftshift(fft2(lnI)); [M,N]=size(I);
    [U,V]=meshgrid((-floor(N/2)):(ceil(N/2)-1), (-floor(M/2)):(ceil(M/2)-1));
    D=sqrt(U.^2+V.^2);
    H=(gh-gl)*(1 - 1./(1+(D./D0).^(2*n))) + gl;
    S=F.*H; out=exp(real(ifft2(ifftshift(S)))); out=mat2gray(out);
end

function J = addSaltPepper(I,p)
    A=im2double(I);
    if size(A,3)==1
        mask=rand(size(A)); J=A; J(mask<=p/2)=0; J(mask>=1-p/2)=1;
    else
        J=A; mask=rand(size(A,1),size(A,2)); salt=mask>=1-p/2; pepper=mask<=p/2;
        for c=1:3, ch=J(:,:,c); ch(pepper)=0; ch(salt)=1; J(:,:,c)=ch; end
    end
    J=im2uint8(J);
end

function J = addGaussianNoise(I,mu,varv)
    A=im2double(I); noise=mu+sqrt(varv)*randn(size(A)); J=A+noise; J=im2uint8(min(max(J,0),1));
end

function out = orderFilter2D(img,n,~,mode)
    A=double(img); r=floor(n/2); if mod(n,2)==0, n=n+1; r=floor(n/2); end
    P=padReplicate(A,r,r); [M,N]=size(A); out=zeros(M,N);
    for i=1:M
        for j=1:N
            win=P(i:i+2*r,j:j+2*r);
            if strcmp(mode,'min'), out(i,j)=min(win(:)); else, out(i,j)=max(win(:)); end
        end
    end
end

function out = medianFilter2D(img,n)
    A=double(img); r=floor(n/2); if mod(n,2)==0, n=n+1; r=floor(n/2); end
    P=padReplicate(A,r,r); [M,N]=size(A); out=zeros(M,N);
    for i=1:M
        for j=1:N
            w=sort(P(i:i+2*r,j:j+2*r)); w=w(:); out(i,j)=w(ceil(numel(w)/2));
        end
    end
end

function out = geometricMeanFilter2D(img,n)
    A=im2double(img); A(A<=0)=1e-6; r=floor(n/2); P=padReplicate(A,r,r); [M,N]=size(A); out=zeros(M,N); k=n*n;
    for i=1:M, for j=1:N, win=P(i:i+2*r,j:j+2*r); out(i,j)=exp(sum(log(win(:)))/k); end, end
end

function out = harmonicMeanFilter2D(img,n)
    A=im2double(img); r=floor(n/2); P=padReplicate(A,r,r); [M,N]=size(A); out=zeros(M,N); k=n*n;
    for i=1:M, for j=1:N, win=P(i:i+2*r,j:j+2*r); out(i,j)=k/sum(1./max(win(:),1e-6)); end, end
end

function out = contraharmonicMeanFilter2D(img,n,Q)
    A=im2double(img); r=floor(n/2); P=padReplicate(A,r,r); [M,N]=size(A); out=zeros(M,N);
    for i=1:M, for j=1:N, win=P(i:i+2*r,j:j+2*r); num=sum(win(:).^(Q+1)); den=sum(win(:).^Q); out(i,j)=num/max(den,1e-12); end, end
end

function out = midpointFilter2D(img,n)
    A=double(img); r=floor(n/2); P=padReplicate(A,r,r); [M,N]=size(A); out=zeros(M,N);
    for i=1:M, for j=1:N, win=P(i:i+2*r,j:j+2*r); out(i,j)=(min(win(:))+max(win(:)))/2; end, end
end

function out = alphaTrimmedMeanFilter2D(img,n,d)
    A=double(img); r=floor(n/2); if d>=n*n, d=n*n-1; end
    P=padReplicate(A,r,r); [M,N]=size(A); out=zeros(M,N); tl=floor(d/2); th=d-tl;
    for i=1:M, for j=1:N, win=sort(P(i:i+2*r,j:j+2*r)); win=win(:); win=win(1+tl:end-th); out(i,j)=mean(win); end, end
end

function K = makeMotionPSF(len,theta)
    L=max(1,round(len)); n=L; if mod(n,2)==0, n=n+1; end
    K=zeros(n); c=(n+1)/2; th=deg2rad(theta);
    x0=c-(L-1)/2*cos(th); y0=c-(L-1)/2*sin(th); x1=c+(L-1)/2*cos(th); y1=c+(L-1)/2*sin(th);
    for t=0:1:L-1
        x=round(x0+t*(x1-x0)/(L-1)); y=round(y0+t*(y1-y0)/(L-1));
        x=min(max(1,x),n); y=min(max(1,y),n); K(y,x)=1;
    end
    K=K/max(sum(K(:)),1);
end

function OTF = psf2otf_local(psf,outSz)
    P=zeros(outSz); [p,q]=size(psf); P(1:p,1:q)=psf; P=circshift(P,-floor([p,q]/2)); OTF=fft2(P);
end

function out = wienerDeconv2D(img,psf,K)
    A=im2double(img); [M,N]=size(A); H=psf2otf_local(psf,[M,N]); G=fft2(A);
    Fhat=(conj(H)./(abs(H).^2 + K)).*G; out=real(ifft2(Fhat)); out=mat2gray(out);
end

function out = autoNotchDenoise(img,numPairs,sigma)
    A=im2double(img); [M,N]=size(A); F=fftshift(fft2(A)); mag=log(1+abs(F));
    [U,V]=meshgrid(1:N,1:M); cx=ceil(N/2); cy=ceil(M/2); R0=min(M,N)/20; centerMask=hypot(U-cx,V-cy)<=R0; mag(centerMask)=0;
    peaks=zeros(numPairs,2); magWork=mag; nb=max(round(min(M,N)/50),3);
    for k=1:numPairs
        [~,idx]=max(magWork(:)); [r,c]=ind2sub(size(magWork),idx); peaks(k,:)=[r,c];
        magWork(max(1,r-nb):min(M,r+nb), max(1,c-nb):min(N,c+nb))=0;
        rs=2*cy-r; cs=2*cx-c;
        if rs>=1 && rs<=M && cs>=1 && cs<=N
            magWork(max(1,rs-nb):min(M,rs+nb), max(1,cs-nb):min(N,cs+nb))=0;
        end
    end
    H=ones(M,N);
    for k=1:numPairs
        r=peaks(k,1); c=peaks(k,2); rs=2*cy-r; cs=2*cx-c;
        D1=sqrt((U-c).^2 + (V-r).^2); D2=sqrt((U-cs).^2 + (V-rs).^2);
        notch = 1 - exp(-(D1.^2)/(2*sigma^2));
        notch2= 1 - exp(-(D2.^2)/(2*sigma^2));
        H=H.*notch.*notch2;
    end
    out = real(ifft2(ifftshift(F.*H))); out=mat2gray(out);
end

end % end main function
