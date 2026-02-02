%% Function body
% objectRecoverFT is the initial value
figure;
for iteration = 1:loop

    for t = images_to_use
% 
% if ismember(iteration, [2 20:100]) && ismember(t, settings.KK_used_in_index)
%     continue;
% end

        kxc = round( (n+1) / 2 + kx(t) / dkx );
        kyc = round( (m+1) / 2 + ky(t) / dky );
        kyl = round( kyc - ( m1 - 1)/2 );kyh = round(kyc + (m1 - 1)/2 );
        kxl = round( kxc - ( n1 - 1)/2 );kxh = round(kxc + (n1 - 1)/2 );
        lowresft_1=objectRecoverFT(kyl:kyh,kxl:kxh).*CTF.*pupil;
        lowres = iF(lowresft_1);
        
        phase = angle(lowres);
        % phase = phase_unwrapCG(phase);
        % LED intensity correction
        % LED_correct_Index(1,t+(iteration-1)*numImg)=(mean(mean(abs(lowres)))/mean(mean(upsample_ratio^2*abs(I(:,:,t)))));
        % if iteration>2   && iteration < 4
        %     I(:,:,t)=I(:,:,t).*LED_correct_Index(1,t+(iteration-1)*numImg); 
        % end 
        
        % phase = phase_unwrapCG(angle(lowres));
            % Unified stray light removal logic
            threshold = [0.055, 0.055, 0.045] * (2^14);
            temp = abs( I(:, :, t) );
            % temp = (2^14)*(temp/max(temp(:)));
            % Apply stray light correction only to specific image indices
            % if t > 25
            %     temp2 = abs(lowres).^2;
            %     temp2 = (2^14)*(temp2./(max(temp2(:))));
            %     mask = (temp < threshold(color_i)) & (temp2 < threshold(color_i));
            %     temp(~mask) = temp2(~mask);
            % end
        
        if iteration < 15
            lowres =(upsample_ratio^2)* ((temp).^0.7).*exp(1j*phase);
        else
            lowres =(upsample_ratio^2)* ((temp).^0.7).*exp(1j*phase);
        end

        lowresft_2 = F(lowres);
        %Object update
        %
        objectRecoverFT(kyl:kyh,kxl:kxh) = objectRecoverFT(kyl:kyh,kxl:kxh) + ...
            abs(pupil) .* conj(pupil) .* (lowresft_2-lowresft_1) / max(abs(pupil(:))) ./ (abs(pupil).^2 + OP_alpha ).* CTF;
        %ePIE
        % objectRecoverFT(kyl:kyh,kxl:kxh) = objectRecoverFT(kyl:kyh,kxl:kxh) + ...
        %     abs(pupil) .* conj(pupil) .* (lowresft_2-lowresft_1) / max(abs(pupil(:))) ./ (abs(pupil).^2 + OP_alpha*(max(abs(pupil(:)))^2) );
        %(rPIE)
        % objectRecoverFT(kyl:kyh,kxl:kxh) = objectRecoverFT(kyl:kyh,kxl:kxh) + conj(CTF.*pupil)./...
        %     ((1-alphaO)*abs(CTF.*pupil).^2+alphaO*max(max(abs(CTF.*pupil).^2))).*(lowresft_2-lowresft_1); 

        %Pupil update
        if iteration > 2
        %
        pupil = pupil + abs(objectRecoverFT(kyl:kyh,kxl:kxh)).*conj(objectRecoverFT(kyl:kyh,kxl:kxh))...
                .*(lowresft_2-lowresft_1)/(max(abs(objectRecoverFT(:))))./ (abs(objectRecoverFT(kyl:kyh,kxl:kxh)).^2 + OP_beta) .* CTF;
        %ePIE
        % pupil = pupil + abs(objectRecoverFT(kyl:kyh,kxl:kxh)).*conj(objectRecoverFT(kyl:kyh,kxl:kxh))...
        %         .*(lowresft_2-lowresft_1)/(max(abs(objectRecoverFT(:))))./ (abs(objectRecoverFT(kyl:kyh,kxl:kxh)).^2 + OP_beta*max(max(abs(objectRecoverFT(kyl:kyh,kxl:kxh)).^2))   ) .* CTF;
        %(rPIE)
        % pupil = pupil + conj(objectRecoverFT(kyl:kyh,kxl:kxh))./((1-alphaP)*abs(objectRecoverFT(kyl:kyh,kxl:kxh)).^2 ...
        %         + alphaP*max(max(abs(objectRecoverFT(kyl:kyh,kxl:kxh)).^2))).*(lowresft_2-lowresft_1);
        end
        pupil = pupil.*CTF;

        %error computing
        Objcrop(:,:,t) = iF(objectRecoverFT(kyl:kyh,kxl:kxh).*pupil);
    end
    % Adaptive step-size

        % err(iteration)= sum(sum(sum(((I-abs(Objcrop).^2).^2)))) /sum(sum(sum(I.^2)));

    % if iteration > 1 && ( err(iteration) - err(iteration - 1) )/err(iteration - 1) > 0.01
    %     OP_alpha =OP_alpha/3*2;
    %     OP_beta = OP_beta/3*2;
    % end
    % 
    % if iteration == 15  
    %         if ifsAIKK == 1
    %             objectRecoverFT = initial_guess;
    %         else
    %             objectRecoverFT = ones(m,m);
    %         end
    %     pupil = exp(1i*angle(pupil)).*CTF;
    %     OP_alpha =0.8;
    %     OP_beta = 0.8;
    %     alphaO = 0.8;                                                             % the parameter of rPIE
    %     alphaP = 0.8;                                                             % the parameter of rPIE
    %     LED_correct_Index = ones(1,loop*numImg);
    % end

    out_obj = iF(objectRecoverFT);
    out_pupil = pupil;
        % 
            subplot(221); imshow(angle(out_pupil),[]); title('pupil phase','FontSize',16)
        subplot(222); imshow(logamp(objectRecoverFT),[]);           title('Intensity','FontSize',16);
        subplot(223); imshow(abs(out_obj),[]);          title('Amp','FontSize',16);
        subplot(224); imshow(angle(out_obj),[]);          title('Phase','FontSize',16);
        drawnow;
end