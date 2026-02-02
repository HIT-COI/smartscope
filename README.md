# Handheld Smartscope for High-Throughput Quantitative Phase Imaging via Sparse Multi-Annular Illumination and Kramers-Kronig Relations

This repository contains code and data for the Handheld Smartscope project.

## Repository Structure

### hardware
3D printable STL files for the handheld smartscope. Feel free to customize and print your own version!

### software
Flutter-based multi-platform mobile application for controlling the smartscope system.

#### Installation & Setup
   - Install Android Studio
   - Import the `software` folder as a new project
   - Upon first import, you will see a dependency prompt:
   
     ![Tutorial Screenshot](resources/Tutorial1.png)

   - Click "Get dependencies" to download required Flutter packages
   - Run [main.dart](software/lib/main.dart)
   
        > 💡 **Note:** You can [download a pre-built APK](https://github.com/HIT-COI/smartscope/releases/download/v0.1.0/app-release.apk) directly, though we recommend building from source to ensure optimal compatibility with your specific device.

   - In [main.dart](software/lib/main.dart), modify the physical PPI value according to your device specifications:

        ```dart
        static const double physicalPPI = 441.0; 
        ```
   
   - In [PreviewParameterPage.dart](software/lib/Pages/PreviewParameterPage.dart), configure key imaging parameters:
   
        ```dart
        // Interval(milliseconds)
        late final ValueNotifier<int> _intervalNotifier = ValueNotifier(2000);
        // Radius (millimeters)
        late final ValueNotifier<double> _radiusNotifier = ValueNotifier(1.0);
        // Spatial spacing (millimeters)
        late final ValueNotifier<double> _spacingNotifier = ValueNotifier(5.7);
        // Coordinates (millimeters)
        late final ValueNotifier<double> _offsetXNotifier = ValueNotifier(50);
        late final ValueNotifier<double> _offsetYNotifier = ValueNotifier(50);
        // Ring overlap ratios
        late final ValueNotifier<double> _firstRingOverlapNotifier = ValueNotifier(0.5);
        late final ValueNotifier<double> _secondRingOverlapNotifier = ValueNotifier(0.4);
        ```

        >  **Note:** The **Image Acquisition** page is the primary functional component of the app. Other pages represent our future work for mobile computational imaging and are not yet fully implemented.

### reconstruction_code

Reconstruction via Sparse Multi-Annular Illumination and Kramers-Kronig Relations.

Two sample datasets are provided:
- **`Mate70_data/`** - Standard scenario
- **`Mate70_Open_data/`** - Open environment

- Run [main_recon.m](reconstruction_code/main_recon.m). Most parameters are pre-configured here.

- In [sAIKK_single_color.m](reconstruction_code/sAIKK_single_color.m), choose whether to apply self-calibration:

    ```matlab
    freqUV_used = freqUV_noCal;  % Without calibration
    % freqUV_used = freqUV_Cal;   % With calibration (recommended)
    ```

- In [load_mat.m](reconstruction_code/load_mat.m), configure preprocessing parameters:

    ```matlab
    ifUseBackImage = 1;        % Use background correction
    useStray = 0;              % Stray light removal
    elimi_dark_current = 1;    % Eliminate dark current
    ```

## License and Citation
This framework is licensed under the MIT License. Please see LICENSE for details.



