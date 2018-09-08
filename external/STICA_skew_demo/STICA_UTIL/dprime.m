function [dp, bias]=dprime(h,fa);%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Given hit rate h and false alarm rate, compute d'.% Note that both h and fa must be between 0 and 1.% e.g. [dp, bias]=dprime(0.52,0.5)if h>1 | h<0 hfaerror('h: dprime needs probs'); end;if fa>1 | fa<0 hfaerror('fa: dprime needs probs'); end;if h>0.99	h=0.99; end;if fa<0.01	fa=0.01; end;	dp = jerfinv(h) - jerfinv(fa);bias = - (jerfinv(h) + jerfinv(fa) ) / 2;% �for i=0:0.1:1 h=i; fa=1-h; y=get_dprime(h,fa); ys=[ys y]; fprintf('h=%.3f fa=%.3f dp=%.3f\n',h,fa,y);end;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%