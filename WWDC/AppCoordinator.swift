//
//  AppCoordinator.swift
//  WWDC
//
//  Created by Guilherme Rambo on 19/04/17.
//  Copyright © 2017 Guilherme Rambo. All rights reserved.
//

import Cocoa
import RealmSwift
import RxSwift
import ConfCore
import PlayerUI

final class AppCoordinator {
    
    private let disposeBag = DisposeBag()
    
    var storage: Storage
    var syncEngine: SyncEngine
    var downloadManager: DownloadManager
    
    var windowController: MainWindowController
    var tabController: MainTabController
    
    var scheduleController: SessionsSplitViewController
    var videosController: SessionsSplitViewController
    
    var currentPlayerController: VideoPlayerViewController?
    
    var currentActivity: NSUserActivity?
    
    init(windowController: MainWindowController) {
        let filePath = PathUtil.appSupportPath + "/ConfCore.realm"
        
        var realmConfig = Realm.Configuration(fileURL: URL(fileURLWithPath: filePath))
        realmConfig.schemaVersion = 5
        realmConfig.migrationBlock = { _, _ in }
        
        let client = AppleAPIClient(environment: .current)
        
        do {
            self.storage = try Storage(realmConfig)
            
            self.syncEngine = SyncEngine(storage: storage, client: client)
            
            self.downloadManager = DownloadManager(storage)
        } catch {
            fatalError("Realm initialization error: \(error)")
        }
        
        self.tabController = MainTabController()
        
        // Schedule
        self.scheduleController = SessionsSplitViewController(listStyle: .schedule)
        scheduleController.identifier = "Schedule"
        let scheduleItem = NSTabViewItem(viewController: scheduleController)
        scheduleItem.label = "Schedule"
        self.tabController.addTabViewItem(scheduleItem)
        
        // Videos
        self.videosController = SessionsSplitViewController(listStyle: .videos)
        videosController.identifier = "Videos"
        let videosItem = NSTabViewItem(viewController: videosController)
        videosItem.label = "Videos"
        self.tabController.addTabViewItem(videosItem)
        
        self.windowController = windowController
        
        setupBindings()
        setupDelegation()
        
        NotificationCenter.default.addObserver(forName: .NSApplicationDidFinishLaunching, object: nil, queue: nil) { _ in self.startup() }
    }
    
    /// The session that is currently selected on the videos tab (observable)
    var selectedSession: Observable<SessionViewModel?> {
        return videosController.listViewController.selectedSession.asObservable()
    }
    
    /// The session that is currently selected on the schedule tab (observable)
    var selectedScheduleItem: Observable<SessionViewModel?> {
        return scheduleController.listViewController.selectedSession.asObservable()
    }
    
    /// The session that is currently selected on the videos tab
    var selectedSessionValue: SessionViewModel? {
        return videosController.listViewController.selectedSession.value
    }
    
    /// The session that is currently selected on the schedule tab
    var selectedScheduleItemValue: SessionViewModel? {
        return scheduleController.listViewController.selectedSession.value
    }
    
    /// The viewModel for the current playback session
    var currentPlaybackViewModel: PlaybackViewModel?
    
    private func setupBindings() {
        selectedSession.subscribeOn(MainScheduler.instance).subscribe(onNext: { [weak self] viewModel in
            self?.videosController.detailViewController.viewModel = viewModel
        }).addDisposableTo(self.disposeBag)
        
        selectedScheduleItem.subscribeOn(MainScheduler.instance).subscribe(onNext: { [weak self] viewModel in
            self?.scheduleController.detailViewController.viewModel = viewModel
        }).addDisposableTo(self.disposeBag)
        
        selectedSession.subscribe(onNext: updateCurrentActivity).addDisposableTo(self.disposeBag)
        selectedScheduleItem.subscribe(onNext: updateCurrentActivity).addDisposableTo(self.disposeBag)
    }
    
    private func setupDelegation() {
        let videoDetail = videosController.detailViewController
        
        videoDetail.shelfController.delegate = self
        videoDetail.summaryController.actionsViewController.delegate = self
        
        let scheduleDetail = scheduleController.detailViewController
        
        scheduleDetail.shelfController.delegate = self
        scheduleDetail.summaryController.actionsViewController.delegate = self
    }
    
    private func updateListsAfterSync() {
        self.videosController.listViewController.sessions = storage.sessions.toArray()
        
        storage.scheduleObservable.subscribe(onNext: { [weak self] instances in
            self?.scheduleController.listViewController.sessionInstances = instances
        }).dispose()
    }
    
    @IBAction func refresh(_ sender: Any?) {
        syncEngine.syncSessionsAndSchedule()
    }
    
    func startup() {
        windowController.contentViewController = tabController
        windowController.showWindow(self)
        
        NotificationCenter.default.addObserver(forName: .SyncEngineDidSyncSessionsAndSchedule, object: nil, queue: OperationQueue.main) { _ in
            self.updateListsAfterSync()
        }
        
        refresh(nil)
        updateListsAfterSync()
    }
    
}
