//
//  CameraViewController.swift
//  HXPhotoPicker
//
//  Created by Slience on 2021/8/30.
//

import UIKit
#if HXPICKER_ENABLE_CAMERA_LOCATION
import CoreLocation
#endif
import AVFoundation

/// 需要有导航栏
#if !targetEnvironment(macCatalyst)
open class CameraViewController: BaseViewController {
    public weak var delegate: CameraViewControllerDelegate?
    
    /// 相机配置
    public var config: CameraConfiguration
    /// 相机类型
    public let type: CameraController.CaptureType
    /// 内部自动dismiss
    public var autoDismiss: Bool = true
    
    /// takePhotoMode = .click 拍照类型
    public var takeType: CameraBottomViewTakeType {
        bottomView.takeType
    }
    
    /// 闪光灯模式
    public var flashMode: AVCaptureDevice.FlashMode {
        cameraManager.flashMode
    }
    
    /// 设置闪光灯模式
    @discardableResult
    public func setFlashMode(_ flashMode: AVCaptureDevice.FlashMode) -> Bool {
        cameraManager.setFlashMode(flashMode)
    }
    
    public init(
        config: CameraConfiguration,
        type: CameraController.CaptureType,
        delegate: CameraViewControllerDelegate? = nil
    ) {
        PhotoManager.shared.createLanguageBundle(languageType: config.languageType)
        PhotoManager.shared.cameraType = config.cameraType
        self.config = config
        self.type = type
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
        self.autoDismiss = config.isAutoBack
    }
    private var didLayoutPreview = false
    
    var previewView: CameraPreviewView!
    var normalPreviewView: CameraNormalPreviewView!
    var cameraManager: CameraManager!
    var bottomView: CameraBottomView!
    var topMaskLayer: CAGradientLayer!
    #if HXPICKER_ENABLE_CAMERA_LOCATION
    var locationManager: CLLocationManager!
    var currentLocation: CLLocation?
    var didLocation: Bool = false
    #endif
    
    var firstShowFilterName = true
    var currentZoomFacto: CGFloat = 1
    
    private var requestCameraSuccess = false
    private var sessionCommitConfiguration = true
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        title = ""
        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all
        view.backgroundColor = .black
        navigationController?.navigationBar.tintColor = .white
        initViews()
        if !UIImagePickerController.isSourceTypeAvailable(.camera) {
            bottomView.isGestureEnable = false
            view.addSubview(bottomView)
            PhotoTools.showConfirm(
                viewController: self,
                title: "相机不可用!".localized,
                message: nil,
                actionTitle: "确定".localized
            ) { [weak self] _ in
                self?.backClick(true)
            }
            return
        }
        AssetManager.requestCameraAccess { isGranted in
            if isGranted {
                self.setupCamera()
            }else {
                self.bottomView.isGestureEnable = false
                self.view.addSubview(self.bottomView)
                PhotoTools.showNotCameraAuthorizedAlert(
                    viewController: self
                ) { [weak self] in
                    self?.backClick(true)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    private func initViews() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            cameraManager = CameraManager(config: config)
            cameraManager.flashModeDidChanged = { [weak self] in
                guard let self = self else { return }
                self.delegate?.cameraViewController(self, flashModeDidChanged: $0)
            }
            if config.cameraType == .metal {
                cameraManager.captureDidOutput = { [weak self] pixelBuffer in
                    guard let self = self else { return }
                    self.previewView.pixelBuffer = pixelBuffer
                }
                previewView = CameraPreviewView(
                    config: config,
                    cameraManager: cameraManager
                )
                previewView.delegate = self
            }else {
                normalPreviewView = CameraNormalPreviewView(config: config)
                normalPreviewView.delegate = self
            }
            
            
            topMaskLayer = PhotoTools.getGradientShadowLayer(true)
            
            #if HXPICKER_ENABLE_CAMERA_LOCATION
            locationManager = CLLocationManager()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = kCLDistanceFilterNone
            locationManager.requestWhenInUseAuthorization()
            #endif
        }
        
        bottomView = CameraBottomView(
            tintColor: config.tintColor,
            takePhotoMode: config.takePhotoMode
        )
        bottomView.delegate = self
    }
    func backClick(_ isCancel: Bool = false) {
        if isCancel {
            delegate?.cameraViewController(didCancel: self)
        }
        if autoDismiss {
            dismiss(animated: true, completion: nil)
        }
    }
    open override func deviceOrientationWillChanged(notify: Notification) {
        if config.cameraType == .metal {
            guard let previewView = previewView else { return }
            didLayoutPreview = false
            previewView.resetMask(nil)
        }else {
            guard let previewView = normalPreviewView else { return }
            didLayoutPreview = false
            previewView.resetMask(nil)
        }
    }
    open override func deviceOrientationDidChanged(notify: Notification) {
        if config.cameraType == .metal {
            guard let previewView = previewView else { return }
            previewView.resetOrientation()
            previewView.removeMask(true)
        }else {
            guard let previewView = normalPreviewView else { return }
            previewView.resetOrientation()
            previewView.removeMask(true)
        }
    }
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutSubviews()
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let nav = navigationController else {
            return
        }
        let navHeight = nav.navigationBar.frame.maxY
        nav.navigationBar.setBackgroundImage(
            UIImage.image(
                for: .clear,
                havingSize: CGSize(width: view.width, height: navHeight)
            ),
            for: .default
        )
        nav.navigationBar.shadowImage = UIImage()
    }
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if requestCameraSuccess {
            cameraManager.sessionQueue.async {
                if !self.sessionCommitConfiguration {
                    self.cameraManager.session.commitConfiguration()
                }
                self.cameraManager.startRunning(applyQueue: false)
            }
        }
    }
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard UIImagePickerController.isSourceTypeAvailable(.camera), let cameraManager else { return }
        let isFront = cameraManager.activeCamera?.position == .front
        DispatchQueue.global().async {
            if let sampleBuffer = PhotoManager.shared.sampleBuffer,
               let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
               let imageData = PhotoTools.jpegData(withPixelBuffer: pixelBuffer, attachments: nil) {
                var image = UIImage(data: imageData)
                if self.config.cameraType == .normal {
                    image = image?.rotation(to: .right)
                }
                if isFront {
                    image = image?.rotation(to: .upMirrored)
                }
                PhotoManager.shared.cameraPreviewImage = image?.scaleImage(toScale: 0.5)
                PhotoManager.shared.saveCameraPreview()
                PhotoManager.shared.sampleBuffer = nil
            }
        }
        cameraManager.stopRunning()
        if config.cameraType == .metal {
            cameraManager.resetFilter()
        }
    }
    
    func layoutSubviews() {
        let previewRect: CGRect
        if UIDevice.isPad || !UIDevice.isPortrait {
            if UIDevice.isPad {
                previewRect = view.bounds
            }else {
                let size = CGSize(width: view.height * 16 / 9, height: view.height)
                previewRect = CGRect(
                    x: (view.width - size.width) * 0.5,
                    y: (view.height - size.height) * 0.5,
                    width: size.width, height: size.height
                )
            }
        }else {
            let size = CGSize(width: view.width, height: view.width / 9 * 16)
            previewRect = CGRect(
                x: (view.width - size.width) * 0.5,
                y: (view.height - size.height) * 0.5,
                width: size.width, height: size.height
            )
        }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            if !didLayoutPreview && AssetManager.cameraAuthorizationStatus() == .authorized {
                if config.cameraType == .metal {
                    previewView.frame = previewRect
                }else {
                    normalPreviewView.frame = previewRect
                }
                didLayoutPreview = true
            }
        }
        
        let bottomHeight: CGFloat = 130
        let bottomY: CGFloat
        if UIDevice.isPortrait && !UIDevice.isPad {
            if UIDevice.isAllIPhoneX {
                bottomY = view.height - 110 - previewRect.minY
            }else {
                bottomY = view.height - bottomHeight
            }
        }else {
            bottomY = view.height - bottomHeight
        }
        bottomView.frame = CGRect(
            x: 0,
            y: bottomY,
            width: view.width,
            height: bottomHeight
        )
        if let nav = navigationController, UIImagePickerController.isSourceTypeAvailable(.camera) {
            topMaskLayer.frame = CGRect(
                x: 0,
                y: 0,
                width: view.width,
                height: nav.navigationBar.frame.maxY + 10
            )
        }
    }
    
    open override var prefersStatusBarHidden: Bool {
        config.prefersStatusBarHidden
    }
    open override var shouldAutorotate: Bool {
        config.shouldAutorotate
    }
    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        config.supportedInterfaceOrientations
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    deinit {
        #if HXPICKER_ENABLE_CAMERA_LOCATION
        if allowLocation && didLocation {
            locationManager.stopUpdatingLocation()
        }
        #endif
        DeviceOrientationHelper.shared.stopDeviceOrientationNotifier()
    }
}

extension CameraViewController {
    
    @objc
    func willEnterForeground() {
    }
    @objc
    func didEnterBackground() {
        if config.cameraType == .metal {
            previewView.clearMeatalPixelBuffer()
            cameraManager.resetFilter()
        }
    }
    
    @objc
    public func didSwitchCameraClick() {
        if config.cameraType == .metal {
            previewView.metalView.isPaused = true
            previewView.pixelBuffer = nil
        }
        do {
            try cameraManager.switchCameras()
        } catch {
            HXLog("相机前后摄像头切换失败: \(error)")
            switchCameraFailed()
        }
        delegate?.cameraViewController(
            self,
            didSwitchCameraCompletion: cameraManager.activeCamera?.position ?? .unspecified
        )
        if !cameraManager.setFlashMode(config.flashMode) {
            cameraManager.setFlashMode(.off)
        }
        resetZoom()
        if config.cameraType == .metal {
            previewView.resetOrientation()
            cameraManager.resetFilter()
            previewView.metalView.isPaused = false
        }else {
            guard let connection = normalPreviewView.previewLayer?.connection else {
                return
            }
            if cameraManager.activeCamera?.position == .front {
                connection.isVideoMirrored = true
            }else {
                connection.isVideoMirrored = false
            }
            normalPreviewView.resetOrientation()
        }
    }
    
    func switchCameraFailed() {
        ProgressHUD.showWarning(
            addedTo: view,
            text: "摄像头切换失败!".localized,
            animated: true,
            delayHide: 1.5
        )
    }
    
    func resetZoom() {
        cameraManager.zoomFacto = 1
        if config.cameraType == .metal {
            previewView.effectiveScale = 1
        }else {
            normalPreviewView.effectiveScale = 1
        }
    }
    
    func setupCamera() {
        DeviceOrientationHelper
            .shared
            .startDeviceOrientationNotifier()
        if config.cameraType == .metal {
            view.addSubview(previewView)
        }else {
            view.addSubview(normalPreviewView)
        }
        view.addSubview(bottomView)
        cameraManager.sessionQueue.async {
            do {
                self.sessionCommitConfiguration = false
                self.cameraManager.session.beginConfiguration()
                try self.cameraManager.startSession()
                var needAddAudio = false
                switch self.type {
                case .photo:
                    try self.cameraManager.addPhotoOutput()
                case .video:
                    needAddAudio = true
                case .all:
                    try self.cameraManager.addPhotoOutput()
                    needAddAudio = true
                }
                self.cameraManager.addVideoOutput()
                if !needAddAudio {
                    self.addOutputCompletion()
                }else {
                    self.addAudioInput()
                }
            } catch {
                self.cameraManager.session.commitConfiguration()
                DispatchQueue.main.async {
                    PhotoTools.showConfirm(
                        viewController: self,
                        title: "相机初始化失败!".localized,
                        message: nil,
                        actionTitle: "确定".localized
                    ) { [weak self] _ in
                        self?.backClick(true)
                    }
                }
            }
        }
//        DispatchQueue.global().async {
//        }
    }
    
    func addAudioInput() {
        AVCaptureDevice.requestAccess(for: .audio) { isGranted in
            self.cameraManager.sessionQueue.async {
//            DispatchQueue.global().async {
                if isGranted {
                    do {
                        try self.cameraManager.addAudioInput()
                        self.cameraManager.addAudioOutput()
                    } catch {
                        DispatchQueue.main.async {
                            self.addAudioInputFailed()
                        }
                    }
                }else {
                    DispatchQueue.main.async {
                        PhotoTools.showAlert(
                            viewController: self,
                            title: "无法使用麦克风".localized,
                            message: "请在设置-隐私-相机中允许访问麦克风".localized,
                            leftActionTitle: "取消".localized,
                            rightActionTitle: "前往系统设置".localized
                        ) { _ in
                            self.addAudioInputFailed()
                        } rightHandler: { _ in
                            PhotoTools.openSettingsURL()
                        }
                    }
                }
                self.addOutputCompletion()
            }
        }
    }
    
    func addAudioInputFailed() {
        ProgressHUD.showWarning(
            addedTo: self.view,
            text: "麦克风添加失败，录制视频会没有声音哦!".localized,
            animated: true,
            delayHide: 1.5
        )
    }
    
    func addOutputCompletion() {
        cameraManager.session.commitConfiguration()
        sessionCommitConfiguration = true
        cameraManager.startRunning(applyQueue: false)
        if config.cameraType == .normal {
            normalPreviewView.setSession(cameraManager.session)
        }
        requestCameraSuccess = true
        DispatchQueue.main.async {
            if self.config.cameraType == .metal {
                self.previewView.resetOrientation()
            }
            self.sessionCompletion()
        }
    }
    
    func sessionCompletion() {
        if cameraManager.canSwitchCameras() {
            addSwithCameraButton()
        }
        if config.cameraType == .metal {
            previewView.setupGestureRecognizer()
        }else {
            normalPreviewView.setupGestureRecognizer()
        }
        bottomView.addGesture(for: type)
        #if HXPICKER_ENABLE_CAMERA_LOCATION
        startLocation()
        #endif
    }
    
    func addSwithCameraButton() {
        view.layer.addSublayer(topMaskLayer)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: "hx_camera_overturn".image,
            style: .plain,
            target: self,
            action: #selector(didSwitchCameraClick)
        )
    }
}
#endif
