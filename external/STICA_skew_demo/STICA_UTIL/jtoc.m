function a = jtoc;%global TICTOC%interval = etime(clock,TICTOC);a=toc;if a<=60	fprintf('Elapsed time = %.1f  secs.\n',a);end;if a>60 & a < 3600	a=a/60;	fprintf('Elapsed time = %.2f  mins.\n',a);end;if a>=3600	a = a/3600;	mins = (a-floor(a))*60 ;	fprintf('Elapsed time = %.0f hours and %.0f mins.\n',a,mins);end;