import KsApi
import Prelude
import ReactiveCocoa
import ReactiveExtensions
import Result

public struct ReferrersRowData {
  public let country: Project.Country
  public let referrers: [ProjectStatsEnvelope.ReferrerStats]
}

extension ReferrersRowData: Equatable {}
public func == (lhs: ReferrersRowData, rhs: ReferrersRowData) -> Bool {
  return lhs.country == rhs.country && lhs.referrers == rhs.referrers
}

public protocol DashboardReferrersCellViewModelInputs {
  /// Call when the Backers button is tapped.
  func backersButtonTapped()

  /// Call to configure cell with cumulative and referral stats.
  func configureWith(cumulative cumulative: ProjectStatsEnvelope.CumulativeStats,
                                project: Project,
                                referrers: [ProjectStatsEnvelope.ReferrerStats])

  /// Call when the Percent button is tapped.
  func percentButtonTapped()

  /// Call when the Pledged button is tapped.
  func pledgedButtonTapped()

  /// Call when the Show more referrers button is tapped.
  func showMoreReferrersTapped()

  /// Call when the Source button is tapped.
  func sourceButtonTapped()
}

public protocol DashboardReferrersCellViewModelOutputs {
  /// Emits the average pledge text to be displayed.
  var averagePledgeText: Signal<String, NoError> { get }

  /// Emits the custom percent text to be displayed.
  var customPercentText: Signal<String, NoError> { get }

  /// Emits the pledged via custom text to be displayed.
  var customPledgedText: Signal<String, NoError> { get }

  /// Emits a boolean to determine whether or not custom stats should be hidden.
  var customStackViewHidden: Signal<Bool, NoError> { get }

  /// Emits the external pledge percentage to be displayed in a chart.
  var externalPercentage: Signal<Double, NoError> { get }

  /// Emits the percent pledged via external text to be displayed.
  var externalPercentText: Signal<String, NoError> { get }

  /// Emits the pledged via external text to be displayed.
  var externalPledgedText: Signal<String, NoError> { get }

  /// Emits the internal pledge percentage to be displayed in a chart.
  var internalPercentage: Signal<Double, NoError> { get }

  /// Emits the percent pledged via internal text to be displayed.
  var internalPercentText: Signal<String, NoError> { get }

  /// Emits the pledged via internal text to be displayed.
  var internalPledgedText: Signal<String, NoError> { get }

  /// Emits when should notify the delegate that referrer rows have been added to the stack view.
  var notifyDelegateAddedReferrerRows: Signal<Void, NoError> { get }

  /// Emits the referrers row data to be displayed in each referrers stack view row.
  var referrersRowData: Signal<ReferrersRowData, NoError> { get }

  /// Emits a boolean to determine when the show more referrers button should be hidden.
  var showMoreReferrersButtonHidden: Signal<Bool, NoError> { get }
}

public protocol DashboardReferrersCellViewModelType {
  var inputs: DashboardReferrersCellViewModelInputs { get }
  var outputs: DashboardReferrersCellViewModelOutputs { get }
}

public final class DashboardReferrersCellViewModel: DashboardReferrersCellViewModelInputs,
  DashboardReferrersCellViewModelOutputs, DashboardReferrersCellViewModelType {

  // swiftlint:disable function_body_length
  public init() {
    let cumulativeProjectStats = cumulativeProjectStatsProperty.signal.ignoreNil()

    let country = cumulativeProjectStats.map { _, project, _ in project.country }

    let referrers = cumulativeProjectStats.map { _, _, stats in stats }

    self.averagePledgeText = cumulativeProjectStats
      .map { cumulative, project, _ in
        Format.currency(cumulative.averagePledge, country: project.country)
    }

    let customReferrers = referrers
      .map { referrers in referrers.filter { $0.referrerType == .custom } }

    let customPledgedAmount = customReferrers
      .map { $0.reduce(0) { accum, referrer in accum + referrer.pledged } }

    let externalReferrers = referrers
      .map { referrers in referrers.filter { $0.referrerType == .external } }

    let externalPledgedAmount = externalReferrers
      .map { $0.reduce(0) { accum, referrer in accum + referrer.pledged } }

    let internalReferrers = referrers
      .map { referrers in referrers.filter { $0.referrerType == .`internal` } }

    let internalPledgedAmount = internalReferrers
      .map { $0.reduce(0) { accum, referrer in accum + referrer.pledged } }

    self.customPercentText = customReferrers
      .map { $0.reduce(0.0) { accum, referrer in accum + referrer.percentageOfDollars } }
      .map { Format.percentage($0) }

    self.customPledgedText = combineLatest(customPledgedAmount, country)
      .map { pledged, country in Format.currency(pledged, country: country) }

    self.customStackViewHidden = customReferrers.map { $0.isEmpty }

    self.externalPercentage = externalReferrers
      .map { $0.reduce(0.0) { accum, referrer in accum + referrer.percentageOfDollars } }

    self.externalPercentText = self.externalPercentage.map { Format.percentage($0) }

    self.externalPledgedText = combineLatest(externalPledgedAmount, country)
      .map { pledged, country in Format.currency(pledged, country: country) }

    self.internalPercentage = internalReferrers
      .map { $0.reduce(0.0) { accum, referrer in accum + referrer.percentageOfDollars } }

    self.internalPercentText = self.internalPercentage.map { Format.percentage($0) }

    self.internalPledgedText = combineLatest(internalPledgedAmount, country)
      .map { pledged, country in Format.currency(pledged, country: country) }

    let sortedByPledgedOrPercent = referrers.sort { $0.pledged > $1.pledged }

    let initialSort = sortedByPledgedOrPercent

    let sortedByBackers = referrers
      .takeWhen(self.backersButtonTappedProperty.signal)
      .sort { $0.backersCount > $1.backersCount }

    let sortedByPercent = sortedByPledgedOrPercent
      .takeWhen(self.percentButtonTappedProperty.signal)

    let sortedByPledged = sortedByPledgedOrPercent
      .takeWhen(self.pledgedButtonTappedProperty.signal)

    let sortedBySource = referrers
      .takeWhen(self.sourceButtonTappedProperty.signal)
      .sort { $0.referrerName.lowercaseString < $1.referrerName.lowercaseString }

    let allReferrers = Signal.merge(
      initialSort,
      sortedByBackers,
      sortedByPercent,
      sortedByPledged,
      sortedBySource
    )

    let allReferrersRowData = combineLatest(country, allReferrers)
      .map { ReferrersRowData(country: $0, referrers: $1) }

    let showMoreReferrersButtonIsHidden = Signal.merge(
      referrers.map { $0.count < 6 },
      showMoreReferrersTappedProperty.signal.mapConst(true)
    )

    self.showMoreReferrersButtonHidden = showMoreReferrersButtonIsHidden.skipRepeats()

    self.referrersRowData = combineLatest(allReferrersRowData, showMoreReferrersButtonIsHidden)
      .map { rowData, isHidden in
        let refCount = rowData.referrers.count
        let maxReferrers = isHidden ? rowData.referrers :
          Array(rowData.referrers[0..<(min(3, refCount))])
        return ReferrersRowData(country: rowData.country, referrers: maxReferrers)
    }
    .skipRepeats(==)

    self.notifyDelegateAddedReferrerRows = self.showMoreReferrersTappedProperty.signal

    cumulativeProjectStats
      .takeWhen(self.showMoreReferrersTappedProperty.signal)
      .observeNext { _, project, _ in
        AppEnvironment.current.koala.trackDashboardSeeMoreReferrers(project: project)
    }
  }
  // swiftlint:enable function_body_length

  private let backersButtonTappedProperty = MutableProperty()
  public func backersButtonTapped() {
    self.backersButtonTappedProperty.value = ()
  }

  private let cumulativeProjectStatsProperty = MutableProperty<(ProjectStatsEnvelope.CumulativeStats,
                                                                Project,
                                                                [ProjectStatsEnvelope.ReferrerStats])?>(nil)
  public func configureWith(cumulative cumulative: ProjectStatsEnvelope.CumulativeStats,
                                       project: Project,
                                       referrers: [ProjectStatsEnvelope.ReferrerStats]) {

    self.cumulativeProjectStatsProperty.value = (cumulative, project, referrers)
  }

  private let percentButtonTappedProperty = MutableProperty()
  public func percentButtonTapped() {
    self.percentButtonTappedProperty.value = ()
  }

  private let pledgedButtonTappedProperty = MutableProperty()
  public func pledgedButtonTapped() {
    self.pledgedButtonTappedProperty.value = ()
  }

  private let showMoreReferrersTappedProperty = MutableProperty()
  public func showMoreReferrersTapped() {
    self.showMoreReferrersTappedProperty.value = ()
  }

  private let sourceButtonTappedProperty = MutableProperty()
  public func sourceButtonTapped() {
    self.sourceButtonTappedProperty.value = ()
  }

  public let averagePledgeText: Signal<String, NoError>
  public let customPercentText: Signal<String, NoError>
  public let customPledgedText: Signal<String, NoError>
  public let customStackViewHidden: Signal<Bool, NoError>
  public let externalPercentage: Signal<Double, NoError>
  public let externalPercentText: Signal<String, NoError>
  public let externalPledgedText: Signal<String, NoError>
  public let internalPercentage: Signal<Double, NoError>
  public let internalPercentText: Signal<String, NoError>
  public let internalPledgedText: Signal<String, NoError>
  public let notifyDelegateAddedReferrerRows: Signal<Void, NoError>
  public let referrersRowData: Signal<ReferrersRowData, NoError>
  public let showMoreReferrersButtonHidden: Signal<Bool, NoError>

  public var inputs: DashboardReferrersCellViewModelInputs { return self }
  public var outputs: DashboardReferrersCellViewModelOutputs { return self }
}
