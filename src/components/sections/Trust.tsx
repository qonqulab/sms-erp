import { locations } from '@/lib/data';

const Trust = () => {
  return (
    <section className="py-32 px-4 sm:px-6 lg:px-8">
      <div className="max-w-4xl mx-auto text-center">
        <div className="mb-20">
          <h2 className="text-4xl md:text-5xl font-bold mb-6 text-gray-900">
            Technicians Available 24/7
          </h2>
          <p className="text-xl text-gray-600 max-w-3xl mx-auto leading-relaxed">
            On-site, immediate, and committed until completion. No excuses, no delays.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8">
          <div>
            <div className="hidden">
              <svg className="w-10 h-10 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <h3 className="text-2xl font-bold mb-3 text-gray-900">24/7 Support</h3>
            <p className="text-gray-600 text-lg">Hotline always answered by technicians</p>
          </div>

          <div>
            <div className="hidden">
              <svg className="w-10 h-10 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            </div>
            <h3 className="text-2xl font-bold mb-3 text-gray-900">{locations.length} Locations</h3>
            <p className="text-gray-600 text-lg">{locations.join(', ')}</p>
          </div>

          <div>
            <div className="hidden">
              <svg className="w-10 h-10 text-orange-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <h3 className="text-2xl font-bold mb-3 text-gray-900">On-Site Service</h3>
            <p className="text-gray-600 text-lg">Immediate response, same-day visits</p>
          </div>

          <div>
            <div className="hidden">
              <svg className="w-10 h-10 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
            <h3 className="text-2xl font-bold mb-3 text-gray-900">Completion Guarantee</h3>
            <p className="text-gray-600 text-lg">We stay until the job is 100% done</p>
          </div>
        </div>
      </div>
    </section>
  );
};

export default Trust;

